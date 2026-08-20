#include "ModalRequestQueue.h"

#include <algorithm>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <utility>

struct ModalRequestQueue::State {
    enum class Status {
        Waiting,
        Active,
        Completed,
    };

    Status status = Status::Waiting;
};

struct ModalRequestQueue::Coordinator {
    std::mutex mutex;
    std::condition_variable changed;
    std::deque<std::shared_ptr<State>> requests;
};

ModalRequestQueue::Request::Request(
    std::shared_ptr<Coordinator> coordinator,
    std::shared_ptr<State> state)
    : coordinator_(std::move(coordinator)), state_(std::move(state)) {}

ModalRequestQueue::Request::~Request() {
    cancel();
}

ModalRequestQueue::Request::Request(Request&& other) noexcept
    : coordinator_(std::move(other.coordinator_)),
      state_(std::move(other.state_)) {}

ModalRequestQueue::Request& ModalRequestQueue::Request::operator=(
    Request&& other) noexcept {
    if(this == &other) return *this;
    cancel();
    coordinator_ = std::move(other.coordinator_);
    state_ = std::move(other.state_);
    return *this;
}

bool ModalRequestQueue::Request::active() const {
    if(!coordinator_ || !state_) return false;
    std::lock_guard<std::mutex> lock(coordinator_->mutex);
    return state_->status == State::Status::Active;
}

bool ModalRequestQueue::Request::completed() const {
    if(!coordinator_ || !state_) return true;
    std::lock_guard<std::mutex> lock(coordinator_->mutex);
    return state_->status == State::Status::Completed;
}

void ModalRequestQueue::Request::waitUntilActive() const {
    if(!coordinator_ || !state_) return;
    std::unique_lock<std::mutex> lock(coordinator_->mutex);
    coordinator_->changed.wait(lock, [this] {
        return state_->status != State::Status::Waiting;
    });
}

void ModalRequestQueue::Request::waitUntilCompleted() const {
    if(!coordinator_ || !state_) return;
    std::unique_lock<std::mutex> lock(coordinator_->mutex);
    coordinator_->changed.wait(lock, [this] {
        return state_->status == State::Status::Completed;
    });
}

bool ModalRequestQueue::Request::complete() {
    if(!coordinator_ || !state_) return false;
    std::lock_guard<std::mutex> lock(coordinator_->mutex);
    if(state_->status != State::Status::Active ||
       coordinator_->requests.empty() ||
       coordinator_->requests.front() != state_) {
        return false;
    }

    state_->status = State::Status::Completed;
    coordinator_->requests.pop_front();
    if(!coordinator_->requests.empty()) {
        coordinator_->requests.front()->status = State::Status::Active;
    }
    coordinator_->changed.notify_all();
    return true;
}

void ModalRequestQueue::Request::cancel() {
    if(!coordinator_ || !state_) return;
    {
        std::lock_guard<std::mutex> lock(coordinator_->mutex);
        if(state_->status != State::Status::Completed) {
            auto request = std::find(coordinator_->requests.begin(),
                                     coordinator_->requests.end(), state_);
            bool wasActive = request != coordinator_->requests.end() &&
                             request == coordinator_->requests.begin();
            if(request != coordinator_->requests.end()) {
                coordinator_->requests.erase(request);
            }
            state_->status = State::Status::Completed;
            if(wasActive && !coordinator_->requests.empty()) {
                coordinator_->requests.front()->status = State::Status::Active;
            }
            coordinator_->changed.notify_all();
        }
    }
    state_.reset();
    coordinator_.reset();
}

ModalRequestQueue::ModalRequestQueue()
    : coordinator_(std::make_shared<Coordinator>()) {}

ModalRequestQueue::Request ModalRequestQueue::enqueue() {
    auto state = std::make_shared<State>();
    {
        std::lock_guard<std::mutex> lock(coordinator_->mutex);
        if(coordinator_->requests.empty()) state->status = State::Status::Active;
        coordinator_->requests.push_back(state);
    }
    return Request(coordinator_, std::move(state));
}
