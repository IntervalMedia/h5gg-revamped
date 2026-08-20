#include "TargetSession.h"

#include "MemoryValue.h"

#include <utility>

TargetProcess::TargetProcess()
    : pid_(0), port_(MACH_PORT_NULL), releaser_(nullptr) {}

TargetProcess::TargetProcess(pid_t pid,
                             mach_port_t port,
                             H5GGTaskPortReleaser releaser)
    : pid_(pid), port_(port), releaser_(releaser) {}

TargetProcess::~TargetProcess() {
    reset();
}

TargetProcess::TargetProcess(TargetProcess&& other) noexcept
    : pid_(other.pid_), port_(other.port_), releaser_(other.releaser_) {
    other.pid_ = 0;
    other.port_ = MACH_PORT_NULL;
    other.releaser_ = nullptr;
}

TargetProcess& TargetProcess::operator=(TargetProcess&& other) noexcept {
    if(this == &other) return *this;
    reset();
    pid_ = other.pid_;
    port_ = other.port_;
    releaser_ = other.releaser_;
    other.pid_ = 0;
    other.port_ = MACH_PORT_NULL;
    other.releaser_ = nullptr;
    return *this;
}

pid_t TargetProcess::pid() const {
    return pid_;
}

mach_port_t TargetProcess::port() const {
    return port_;
}

bool TargetProcess::valid() const {
    return pid_ > 0 && port_ != MACH_PORT_NULL;
}

bool TargetProcess::ownsPort() const {
    return port_ != MACH_PORT_NULL && releaser_ != nullptr;
}

void TargetProcess::reset() {
    if(port_ != MACH_PORT_NULL && releaser_) releaser_(port_);
    pid_ = 0;
    port_ = MACH_PORT_NULL;
    releaser_ = nullptr;
}

MemorySession::MemorySession(TargetProcess target,
                             JJMemoryEngine* engine,
                             H5GGMemoryEngineDeleter engineDeleter)
    : target_(std::move(target)),
      engine_(engine),
      engineDeleter_(engineDeleter),
      firstSearchDone_(false),
      lastSearchType_(JJ_Search_Type_Error) {}

MemorySession::~MemorySession() {
    if(engine_ && engineDeleter_) engineDeleter_(engine_);
}

const TargetProcess& MemorySession::target() const {
    return target_;
}

JJMemoryEngine* MemorySession::engine() const {
    return engine_;
}

bool MemorySession::firstSearchDone() const {
    return firstSearchDone_;
}

int MemorySession::lastSearchType() const {
    return lastSearchType_;
}

void MemorySession::markSearchDone(int type) {
    firstSearchDone_ = true;
    lastSearchType_ = type;
}

void MemorySession::resetSearchState() {
    firstSearchDone_ = false;
    lastSearchType_ = JJ_Search_Type_Error;
}

void MemorySession::replaceEngine(JJMemoryEngine* engine,
                                  H5GGMemoryEngineDeleter engineDeleter) {
    if(engine_ != engine && engine_ && engineDeleter_) engineDeleter_(engine_);
    engine_ = engine;
    engineDeleter_ = engineDeleter;
    resetSearchState();
}
