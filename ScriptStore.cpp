#include "ScriptStore.h"

#include "FileNames.h"

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

static bool isValidUTF8(const std::string& text) {
    size_t index = 0;
    while(index < text.size()) {
        uint8_t first = static_cast<uint8_t>(text[index]);
        if(first <= 0x7F) {
            index++;
            continue;
        }

        size_t continuationCount = 0;
        uint32_t codePoint = 0;
        uint32_t minimum = 0;
        if((first & 0xE0) == 0xC0) {
            continuationCount = 1;
            codePoint = first & 0x1F;
            minimum = 0x80;
        } else if((first & 0xF0) == 0xE0) {
            continuationCount = 2;
            codePoint = first & 0x0F;
            minimum = 0x800;
        } else if((first & 0xF8) == 0xF0) {
            continuationCount = 3;
            codePoint = first & 0x07;
            minimum = 0x10000;
        } else {
            return false;
        }

        if(index + continuationCount >= text.size()) return false;
        for(size_t offset = 1; offset <= continuationCount; offset++) {
            uint8_t continuation = static_cast<uint8_t>(text[index + offset]);
            if((continuation & 0xC0) != 0x80) return false;
            codePoint = (codePoint << 6) | (continuation & 0x3F);
        }
        if(codePoint < minimum || codePoint > 0x10FFFF ||
           (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            return false;
        }
        index += continuationCount + 1;
    }
    return true;
}

static std::string systemError(const char* operation, int error) {
    return std::string(operation) + ": " + std::strerror(error);
}

static bool caseInsensitiveLess(const std::string& left,
                                const std::string& right) {
    size_t shared = std::min(left.size(), right.size());
    for(size_t index = 0; index < shared; index++) {
        unsigned char leftValue = static_cast<unsigned char>(left[index]);
        unsigned char rightValue = static_cast<unsigned char>(right[index]);
        int lowerLeft = std::tolower(leftValue);
        int lowerRight = std::tolower(rightValue);
        if(lowerLeft != lowerRight) return lowerLeft < lowerRight;
    }
    if(left.size() != right.size()) return left.size() < right.size();
    return left < right;
}

ScriptStore::ScriptStore(std::string rootDirectory)
    : rootDirectory_(std::move(rootDirectory)) {
    while(rootDirectory_.size() > 1 && rootDirectory_.back() == '/') {
        rootDirectory_.pop_back();
    }
}

bool ScriptStore::fail(std::string error) {
    lastError_ = std::move(error);
    return false;
}

bool ScriptStore::resolve(const char* name,
                          std::string& normalized,
                          std::string& path) {
    normalized.clear();
    path.clear();
    if(rootDirectory_.empty()) return fail("The script directory is unavailable");
    if(!H5GGNormalizeScriptFileName(name, normalized)) {
        return fail("Use a single safe .js or .html file name");
    }
    path = rootDirectory_ + "/" + normalized;
    return true;
}

bool ScriptStore::save(const char* name, const std::string& content) {
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();

    std::string normalized;
    std::string path;
    if(!resolve(name, normalized, path)) return false;
    if(content.size() > MaximumScriptBytes) {
        return fail("Scripts are limited to 2 MB");
    }
    if(!isValidUTF8(content)) return fail("Script content must be valid UTF-8");

    std::string temporaryTemplate = rootDirectory_ + "/.h5gg-script.XXXXXX";
    std::vector<char> temporary(temporaryTemplate.begin(), temporaryTemplate.end());
    temporary.push_back('\0');
    int descriptor = mkstemp(temporary.data());
    if(descriptor < 0) return fail(systemError("Unable to create temporary script", errno));

    bool saved = true;
    int savedError = 0;
    size_t offset = 0;
    while(offset < content.size()) {
        ssize_t count = write(descriptor, content.data() + offset,
                              content.size() - offset);
        if(count < 0 && errno == EINTR) continue;
        if(count <= 0) {
            saved = false;
            savedError = count < 0 ? errno : EIO;
            break;
        }
        offset += static_cast<size_t>(count);
    }
    if(saved && fsync(descriptor) != 0) {
        saved = false;
        savedError = errno;
    }
    if(close(descriptor) != 0 && saved) {
        saved = false;
        savedError = errno;
    }
    if(saved && rename(temporary.data(), path.c_str()) != 0) {
        saved = false;
        savedError = errno;
    }
    if(!saved) {
        unlink(temporary.data());
        return fail(systemError("Unable to save script", savedError));
    }
    return true;
}

bool ScriptStore::load(const char* name, std::string& content) {
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();
    content.clear();

    std::string normalized;
    std::string path;
    if(!resolve(name, normalized, path)) return false;

    int descriptor = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if(descriptor < 0) return fail(systemError("Unable to load script", errno));

    struct stat info = {};
    if(fstat(descriptor, &info) != 0 || !S_ISREG(info.st_mode) ||
       info.st_size < 0 || static_cast<uint64_t>(info.st_size) > MaximumScriptBytes) {
        int error = errno ? errno : EFBIG;
        close(descriptor);
        return fail(systemError("Unable to load script", error));
    }

    content.resize(static_cast<size_t>(info.st_size));
    size_t offset = 0;
    while(offset < content.size()) {
        ssize_t count = read(descriptor, content.data() + offset,
                             content.size() - offset);
        if(count < 0 && errno == EINTR) continue;
        if(count <= 0) {
            int error = count < 0 ? errno : EIO;
            close(descriptor);
            content.clear();
            return fail(systemError("Unable to load script", error));
        }
        offset += static_cast<size_t>(count);
    }
    if(close(descriptor) != 0) {
        content.clear();
        return fail(systemError("Unable to load script", errno));
    }
    if(!isValidUTF8(content)) {
        content.clear();
        return fail("Script content must be valid UTF-8");
    }
    return true;
}

bool ScriptStore::remove(const char* name) {
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();

    std::string normalized;
    std::string path;
    if(!resolve(name, normalized, path)) return false;
    if(unlink(path.c_str()) != 0) {
        return fail(systemError("Unable to delete script", errno));
    }
    return true;
}

std::vector<std::string> ScriptStore::list() {
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();
    std::vector<std::string> scripts;

    DIR* directory = opendir(rootDirectory_.c_str());
    if(!directory) {
        fail(systemError("Unable to list scripts", errno));
        return scripts;
    }

    errno = 0;
    while(dirent* entry = readdir(directory)) {
        std::string name(entry->d_name);
        std::string normalized;
        if(!H5GGNormalizeScriptFileName(name.c_str(), normalized) ||
           normalized != name) {
            continue;
        }

        std::string path = rootDirectory_ + "/" + name;
        struct stat info = {};
        if(lstat(path.c_str(), &info) == 0 && S_ISREG(info.st_mode)) {
            scripts.push_back(std::move(name));
        }
    }
    int readError = errno;
    closedir(directory);
    if(readError != 0) {
        fail(systemError("Unable to list scripts", readError));
        scripts.clear();
        return scripts;
    }

    std::sort(scripts.begin(), scripts.end(), caseInsensitiveLess);
    return scripts;
}

std::string ScriptStore::lastError() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return lastError_;
}
