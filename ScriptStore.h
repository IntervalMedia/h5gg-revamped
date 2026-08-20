#ifndef H5GG_SCRIPT_STORE_H
#define H5GG_SCRIPT_STORE_H

#include <cstddef>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

class ScriptStore {
public:
    static constexpr size_t MaximumScriptBytes = 2 * 1024 * 1024;

    explicit ScriptStore(std::string rootDirectory);

    bool save(const char* name, const std::string& content);
    bool save(const char* name, std::nullopt_t content);
    bool load(const char* name, std::string& content);
    bool remove(const char* name);
    std::vector<std::string> list();
    std::string lastError() const;

private:
    bool resolve(const char* name,
                 std::string& normalized,
                 std::string& path);
    bool saveContent(const char* name,
                     const std::optional<std::string>& content);
    bool fail(std::string error);

    std::string rootDirectory_;
    mutable std::mutex mutex_;
    std::string lastError_;
};

#endif
