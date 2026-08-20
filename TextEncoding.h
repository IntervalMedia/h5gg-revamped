#ifndef H5GG_TEXT_ENCODING_H
#define H5GG_TEXT_ENCODING_H

#include <string>

enum class H5GGUTF8NullPolicy {
    Allow,
    Reject,
};

bool H5GGIsValidUTF8(const std::string& text,
                     H5GGUTF8NullPolicy nullPolicy = H5GGUTF8NullPolicy::Allow);

#endif
