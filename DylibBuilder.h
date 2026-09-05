#ifndef H5GG_DYLIB_BUILDER_H
#define H5GG_DYLIB_BUILDER_H

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

enum class H5GGDylibBuildStatus {
    Completed,
    InvalidRequest,
    UnableToReadSource,
    UnableToReadIcon,
    InvalidIcon,
    UnableToReadMenu,
    InvalidMenu,
    IconTooLarge,
    MenuTooLarge,
    TemplateMismatch,
    UnableToWriteOutput,
    SigningFailed,
};

struct H5GGDylibBuildRequest {
    std::string sourcePath;
    std::string iconPath;
    std::string menuPath;
    std::string outputPath;
};

struct H5GGDylibBuildResult {
    H5GGDylibBuildStatus status = H5GGDylibBuildStatus::InvalidRequest;
    std::string outputPath;
    std::string detail;
    size_t architectureCount = 0;

    bool completed() const;
};

using H5GGDylibIconValidator =
    std::function<bool(const std::vector<uint8_t>&, std::string&)>;
using H5GGDylibSigner =
    std::function<bool(const std::string&, std::string&)>;

class DylibBuilder {
public:
    DylibBuilder(std::vector<uint8_t> iconPlaceholder,
                 std::vector<uint8_t> menuPlaceholder,
                 H5GGDylibIconValidator iconValidator,
                 H5GGDylibSigner signer);

    H5GGDylibBuildResult build(const H5GGDylibBuildRequest& request) const;

private:
    std::vector<uint8_t> iconPlaceholder_;
    std::vector<uint8_t> menuPlaceholder_;
    H5GGDylibIconValidator iconValidator_;
    H5GGDylibSigner signer_;
};

#endif
