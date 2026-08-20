#ifndef H5GG_BRIDGE_METHODS_H
#define H5GG_BRIDGE_METHODS_H

#include <cstddef>
#include <cstdint>

enum H5GGBridgeValueKind : uint8_t {
    H5GGBridgeValueNull = 1 << 0,
    H5GGBridgeValueBoolean = 1 << 1,
    H5GGBridgeValueNumber = 1 << 2,
    H5GGBridgeValueString = 1 << 3,
    H5GGBridgeValueArray = 1 << 4,
    H5GGBridgeValueObject = 1 << 5,
};

struct H5GGBridgeArgument {
    uint8_t allowedKinds;
    bool integerOnly;
    bool hasMinimum;
    bool hasMaximum;
    double minimum;
    double maximum;
    const double* allowedNumbers;
    size_t allowedNumberCount;

    bool accepts(H5GGBridgeValueKind kind, double numberValue = 0) const;
};

constexpr size_t H5GGBridgeMaximumArguments = 4;

struct H5GGBridgeMethod {
    const char* name;
    const char* selector;
    size_t minimumArguments;
    size_t maximumArguments;
    H5GGBridgeArgument arguments[H5GGBridgeMaximumArguments];

    bool acceptsArgumentCount(size_t count) const {
        return count >= minimumArguments && count <= maximumArguments;
    }

    bool acceptsArgument(size_t index,
                         H5GGBridgeValueKind kind,
                         double numberValue = 0) const;
};

const H5GGBridgeMethod* H5GGBridgeMethods(size_t& count);
const H5GGBridgeMethod* H5GGBridgeMethodNamed(const char* name);

#endif
