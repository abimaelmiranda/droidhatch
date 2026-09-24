#pragma once

#include <cstddef>

#include <sys/mman.h>
#include <unistd.h>

namespace droidhatch::agent {

class UniqueFd {
public:
    UniqueFd() = default;
    explicit UniqueFd(int fileDescriptor) : fileDescriptor_(fileDescriptor) {}

    UniqueFd(const UniqueFd&) = delete;
    UniqueFd& operator=(const UniqueFd&) = delete;

    UniqueFd(UniqueFd&& other) noexcept
        : fileDescriptor_(other.release()) {}

    UniqueFd& operator=(UniqueFd&& other) noexcept {
        if (this != &other) {
            reset(other.release());
        }
        return *this;
    }

    ~UniqueFd() {
        reset();
    }

    int get() const {
        return fileDescriptor_;
    }

    explicit operator bool() const {
        return fileDescriptor_ >= 0;
    }

    int release() {
        const int fileDescriptor = fileDescriptor_;
        fileDescriptor_ = -1;
        return fileDescriptor;
    }

    void reset(int fileDescriptor = -1) {
        if (fileDescriptor_ >= 0) {
            close(fileDescriptor_);
        }
        fileDescriptor_ = fileDescriptor;
    }

private:
    int fileDescriptor_ = -1;
};

class MappedRegion {
public:
    MappedRegion() = default;

    MappedRegion(void* address, std::size_t size)
        : address_(address), size_(size) {}

    MappedRegion(const MappedRegion&) = delete;
    MappedRegion& operator=(const MappedRegion&) = delete;

    MappedRegion(MappedRegion&& other) noexcept
        : address_(other.releaseAddress()), size_(other.releaseSize()) {}

    MappedRegion& operator=(MappedRegion&& other) noexcept {
        if (this != &other) {
            reset();
            address_ = other.releaseAddress();
            size_ = other.releaseSize();
        }
        return *this;
    }

    ~MappedRegion() {
        reset();
    }

    void* address() const {
        return address_;
    }

    explicit operator bool() const {
        return address_ != nullptr && address_ != MAP_FAILED;
    }

    void reset(void* address = nullptr, std::size_t size = 0) {
        if (address_ != nullptr && address_ != MAP_FAILED) {
            munmap(address_, size_);
        }
        address_ = address;
        size_ = size;
    }

private:
    void* releaseAddress() {
        void* address = address_;
        address_ = nullptr;
        return address;
    }

    std::size_t releaseSize() {
        const std::size_t size = size_;
        size_ = 0;
        return size;
    }

    void* address_ = nullptr;
    std::size_t size_ = 0;
};

} // namespace droidhatch::agent
