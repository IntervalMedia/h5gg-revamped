#include "DylibBuilder.h"

#include "DylibTemplate.h"
#include "TextEncoding.h"

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <exception>
#include <fcntl.h>
#include <limits>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace {

enum class ReadStatus {
    Completed,
    Unavailable,
    TooLarge,
};

H5GGDylibBuildResult result(H5GGDylibBuildStatus status,
                            std::string detail = {}) {
    H5GGDylibBuildResult buildResult;
    buildResult.status = status;
    buildResult.detail = std::move(detail);
    return buildResult;
}

std::string systemError(const char* operation, int error) {
    return std::string(operation) + ": " + std::strerror(error);
}

ReadStatus readRegularFile(const std::string& path,
                           size_t exclusiveSizeLimit,
                           std::vector<uint8_t>& bytes,
                           std::string& detail) {
    bytes.clear();
    int descriptor = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if(descriptor < 0) {
        detail = systemError("Unable to open file", errno);
        return ReadStatus::Unavailable;
    }

    struct stat info = {};
    if(fstat(descriptor, &info) != 0) {
        int error = errno;
        close(descriptor);
        detail = systemError("Unable to inspect file", error);
        return ReadStatus::Unavailable;
    }
    if(!S_ISREG(info.st_mode) || info.st_size < 0 ||
       static_cast<uintmax_t>(info.st_size) >
           static_cast<uintmax_t>(std::numeric_limits<size_t>::max())) {
        close(descriptor);
        detail = "The path is not a readable regular file";
        return ReadStatus::Unavailable;
    }

    size_t size = static_cast<size_t>(info.st_size);
    if(exclusiveSizeLimit != 0 && size >= exclusiveSizeLimit) {
        close(descriptor);
        return ReadStatus::TooLarge;
    }

    bytes.resize(size);
    size_t offset = 0;
    while(offset < bytes.size()) {
        ssize_t count = read(descriptor, bytes.data() + offset,
                             bytes.size() - offset);
        if(count < 0 && errno == EINTR) continue;
        if(count <= 0) {
            int error = count < 0 ? errno : EIO;
            close(descriptor);
            bytes.clear();
            detail = systemError("Unable to read file", error);
            return ReadStatus::Unavailable;
        }
        offset += static_cast<size_t>(count);
    }
    if(close(descriptor) != 0) {
        bytes.clear();
        detail = systemError("Unable to close file", errno);
        return ReadStatus::Unavailable;
    }
    return ReadStatus::Completed;
}

bool writeAll(int descriptor,
              const std::vector<uint8_t>& bytes,
              std::string& detail) {
    size_t offset = 0;
    while(offset < bytes.size()) {
        ssize_t count = write(descriptor, bytes.data() + offset,
                              bytes.size() - offset);
        if(count < 0 && errno == EINTR) continue;
        if(count <= 0) {
            detail = systemError("Unable to write output", count < 0 ? errno : EIO);
            return false;
        }
        offset += static_cast<size_t>(count);
    }
    if(fsync(descriptor) != 0) {
        detail = systemError("Unable to sync output", errno);
        return false;
    }
    return true;
}

} // namespace

bool H5GGDylibBuildResult::completed() const {
    return status == H5GGDylibBuildStatus::Completed;
}

DylibBuilder::DylibBuilder(std::vector<uint8_t> iconPlaceholder,
                           std::vector<uint8_t> menuPlaceholder,
                           H5GGDylibIconValidator iconValidator,
                           H5GGDylibSigner signer)
    : iconPlaceholder_(std::move(iconPlaceholder)),
      menuPlaceholder_(std::move(menuPlaceholder)),
      iconValidator_(std::move(iconValidator)),
      signer_(std::move(signer)) {}

H5GGDylibBuildResult DylibBuilder::build(
    const H5GGDylibBuildRequest& request) const {
    if(request.sourcePath.empty() || request.iconPath.empty() ||
       request.menuPath.empty() || request.outputPath.empty() ||
       iconPlaceholder_.empty() || menuPlaceholder_.empty() ||
       !iconValidator_ || !signer_) {
        return result(H5GGDylibBuildStatus::InvalidRequest);
    }

    std::string detail;
    std::vector<uint8_t> binary;
    if(readRegularFile(request.sourcePath, 0, binary, detail) !=
           ReadStatus::Completed ||
       binary.empty()) {
        return result(H5GGDylibBuildStatus::UnableToReadSource,
                      std::move(detail));
    }

    std::vector<uint8_t> icon;
    ReadStatus iconRead = readRegularFile(
        request.iconPath, iconPlaceholder_.size(), icon, detail);
    if(iconRead == ReadStatus::TooLarge) {
        return result(H5GGDylibBuildStatus::IconTooLarge);
    }
    if(iconRead != ReadStatus::Completed) {
        return result(H5GGDylibBuildStatus::UnableToReadIcon,
                      std::move(detail));
    }
    if(icon.empty()) return result(H5GGDylibBuildStatus::InvalidIcon);
    std::string validationError;
    if(!iconValidator_(icon, validationError)) {
        return result(H5GGDylibBuildStatus::InvalidIcon,
                      std::move(validationError));
    }

    std::vector<uint8_t> menu;
    ReadStatus menuRead = readRegularFile(
        request.menuPath, menuPlaceholder_.size(), menu, detail);
    if(menuRead == ReadStatus::TooLarge) {
        return result(H5GGDylibBuildStatus::MenuTooLarge);
    }
    if(menuRead != ReadStatus::Completed) {
        return result(H5GGDylibBuildStatus::UnableToReadMenu,
                      std::move(detail));
    }
    std::string menuText(menu.begin(), menu.end());
    if(menu.empty() ||
       !H5GGIsValidUTF8(menuText, H5GGUTF8NullPolicy::Reject)) {
        return result(H5GGDylibBuildStatus::InvalidMenu);
    }

    size_t iconReplacements = H5GGReplaceAllTemplates(
        binary, iconPlaceholder_, icon);
    size_t menuReplacements = H5GGReplaceAllTemplates(
        binary, menuPlaceholder_, menu);
    if(iconReplacements == 0 || iconReplacements != menuReplacements) {
        return result(H5GGDylibBuildStatus::TemplateMismatch);
    }

    std::string temporaryTemplate = request.outputPath + ".tmp.XXXXXX";
    std::vector<char> temporary(temporaryTemplate.begin(), temporaryTemplate.end());
    temporary.push_back('\0');
    int descriptor = mkstemp(temporary.data());
    if(descriptor < 0) {
        return result(H5GGDylibBuildStatus::UnableToWriteOutput,
                      systemError("Unable to create output", errno));
    }

    bool wrote = writeAll(descriptor, binary, detail);
    if(close(descriptor) != 0 && wrote) {
        wrote = false;
        detail = systemError("Unable to close output", errno);
    }
    if(!wrote) {
        unlink(temporary.data());
        return result(H5GGDylibBuildStatus::UnableToWriteOutput,
                      std::move(detail));
    }

    bool signedOutput = false;
    std::string signingError;
    try {
        signedOutput = signer_(temporary.data(), signingError);
    } catch(const std::exception& exception) {
        signingError = exception.what();
    } catch(...) {
        signingError = "The signer raised an unknown exception";
    }
    if(!signedOutput) {
        unlink(temporary.data());
        return result(H5GGDylibBuildStatus::SigningFailed,
                      std::move(signingError));
    }

    if(rename(temporary.data(), request.outputPath.c_str()) != 0) {
        int error = errno;
        unlink(temporary.data());
        return result(H5GGDylibBuildStatus::UnableToWriteOutput,
                      systemError("Unable to publish output", error));
    }

    H5GGDylibBuildResult completed = result(H5GGDylibBuildStatus::Completed);
    completed.outputPath = request.outputPath;
    completed.architectureCount = iconReplacements;
    return completed;
}
