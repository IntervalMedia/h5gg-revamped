#ifndef H5GG_FILE_NAMES_H
#define H5GG_FILE_NAMES_H

#include <string>

bool H5GGIsSafeFileName(const char* name);
bool H5GGNormalizeScriptFileName(const char* name, std::string& normalized);

#endif
