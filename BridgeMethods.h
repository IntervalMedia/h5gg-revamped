#ifndef H5GG_BRIDGE_METHODS_H
#define H5GG_BRIDGE_METHODS_H

#include <cstddef>

struct H5GGBridgeMethod {
    const char* name;
    const char* selector;
    size_t minimumArguments;
    size_t maximumArguments;

    bool acceptsArgumentCount(size_t count) const {
        return count >= minimumArguments && count <= maximumArguments;
    }
};

const H5GGBridgeMethod* H5GGBridgeMethods(size_t& count);
const H5GGBridgeMethod* H5GGBridgeMethodNamed(const char* name);

#endif
