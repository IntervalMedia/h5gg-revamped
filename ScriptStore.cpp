#include "ScriptStore.h"

#include "FileNames.h"
#include "TextEncoding.h"

#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

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
    return saveContent(name, std::optional<std::string>(content));
}

bool ScriptStore::save(const char* name, std::nullopt_t) {
    return saveContent(name, std::nullopt);
}

bool ScriptStore::saveContent(const char* name,
                              const std::optional<std::string>& content) {
    std::lock_guard<std::mutex> lock(mutex_);
    lastError_.clear();

    if(!name || !content) {
        return fail("A file name and content are required");
    }

    std::string normalized;
    std::string path;
    if(!resolve(name, normalized, path)) return false;
    if(content->size() > MaximumScriptBytes) {
        return fail("Scripts are limited to 2 MB");
    }
    if(!H5GGIsValidUTF8(*content)) {
        return fail("Script content must be valid UTF-8");
    }

    std::string temporaryTemplate = rootDirectory_ + "/.h5gg-script.XXXXXX";
    std::vector<char> temporary(temporaryTemplate.begin(), temporaryTemplate.end());
    temporary.push_back('\0');
    int descriptor = mkstemp(temporary.data());
    if(descriptor < 0) return fail(systemError("Unable to create temporary script", errno));

    bool saved = true;
    int savedError = 0;
    size_t offset = 0;
    while(offset < content->size()) {
        ssize_t count = write(descriptor, content->data() + offset,
                              content->size() - offset);
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
    if(fstat(descriptor, &info) != 0) {
        int error = errno;
        close(descriptor);
        return fail(systemError("Unable to load script", error));
    }
    if(!S_ISREG(info.st_mode)) {
        close(descriptor);
        return fail("Unable to load script: not a regular file");
    }
    if(info.st_size < 0 || static_cast<uint64_t>(info.st_size) > MaximumScriptBytes) {
        close(descriptor);
        return fail("Unable to load script: scripts are limited to 2 MB");
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
    if(!H5GGIsValidUTF8(content)) {
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
