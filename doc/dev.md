# Development guide

## Getting the source code

First check out the source code.
The following commands will fetch the latest code and also make
sure that submodules are properly initialized.

```sh
# For this document we will assume you are inside a folder for development.
# We will refer to that as `dev`.
#
# I usually have a folder called `dev` in my user folder and inside a subfolder
# for each software project, here that would be `/home/user/dev/qfield`.
# You are free to choose yours.

git clone git@github.com:opengisch/QField.git
git submodule update --init --recursive
# Alternatively you can ues the following URL in case you have not set up SSH keys for github
#   https://github.com/opengisch/QField.git
```

## Linux

You need to have cmake installed.

You have two options to build QField. Using system packages which will
reuse packages installed from your package manager. Or using vcpkg which
will build all the packages from source.

### Using system packages

This will use your system packages.
Make sure you have installed the appropriate `-dev` or `-devel` packages
using your system package manager.
This is much faster to build than the using vcpkg and often the preferred
development method.

### Configure
```sh
cmake -S QField -B build
```

### Using vcpkg

This will build the complete dependency chain from scratch.
Except Qt which is still taken from the system. You can also try
to build Qt, it's known to be hard work.

```sh
cmake -S QField -B build -DSYSTEM_QT=ON
```

Since this is now building a lot, grab yourself a cold or hot drink
and take a good break. It could well take several hours.

### Build

Now build the application.

```sh
cmake --build build
```

## Macos

You need to have cmake and Xcode installed.

The following line will configure the build.

```sh
# We call this from the `dev` folder again
cmake -S QField -B build -GXcode -Tbuildsystem=1 -DWITH_VCPKG=ON
```

Please note that this will download and build the complete dependency
chain of QField. If you ever wanted to read a good book, you will have
a couple of hours to get started.

```sh
cmake --build build
```

## Windows

You need to have the following tools available to build

- cmake
- Visual Studio

### Configure

QField on Windows will always be built using vcpkg.

```sh
cmake -S QField -B build
```

### Build

```sh
cmake --build build
```

## Android

Android runs on a number of different CPU architectures.
The most common one is `arm64`. The platform to build for is specified via triplet.

The following triplets are

- `arm64-android`
- `arm-android`
- `x64-android`
- `x86-android`

### Using a docker image

There is a simple script that helps building everything by using a docker image.

```sh
triplet=arm-android ./scripts/build.sh
```

### Building locally

Make sure you have the following tools installed

- cmake
- The Android SDK including NDK
- Qt for Android
- This list is incomplete, please let us know what is missing

To install Qt, `aqtinstall` is a nifty little helper

```sh
pip3 install aqtinstall
aqt install-qt linux android 5.14.2 -m qtcharts
```

#### Configure

```sh
export ANDROID_NDK_HOME=[path to your android ndk]
cmake -S QField \
      -B build \
      -D VCPKG_TARGET_TRIPLET=arm64-android
```

#### Build

```sh
cmake --build build
```
