#ifndef H5GG_MEMORY_RESULTS_H
#define H5GG_MEMORY_RESULTS_H

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

struct result_region {
    uint64_t region_base;
    size_t region_size;
    std::vector<uint32_t> slides;
    std::vector<int8_t> types;

    result_region(uint64_t base, size_t size);

    bool append(uint32_t slide, int8_t type = 0);
    bool hasTypes() const;
    int8_t typeAt(size_t index, int8_t fallback) const;
    bool invariantHolds() const;
};

class Result {
public:
    Result() = default;
    ~Result();

    Result(const Result&) = delete;
    Result& operator=(const Result&) = delete;

    void add(std::unique_ptr<result_region> region);
    void replace(size_t index, std::unique_ptr<result_region> region);
    void removeEmptyRegions();
    void clear();
    void recount();

    size_t count() const;
    size_t regionCount() const;
    result_region* regionAt(size_t index);
    const std::vector<result_region*>& allRegions() const;
    bool invariantHolds() const;

private:
    std::vector<result_region*> regions;
    size_t resultCount = 0;
};

#endif
