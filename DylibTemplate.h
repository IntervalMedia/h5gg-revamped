#ifndef H5GG_DYLIB_TEMPLATE_H
#define H5GG_DYLIB_TEMPLATE_H

#include <cstddef>
#include <cstdint>
#include <vector>

size_t H5GGReplaceAllTemplates(std::vector<uint8_t>& binary,
                               const std::vector<uint8_t>& placeholder,
                               const std::vector<uint8_t>& payload);

#endif
