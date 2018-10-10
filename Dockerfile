FROM phusion/baseimage:0.9.22

LABEL maintainer="anthonymonori@gmail.com"

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

## Set up Android related environment vars
ENV ANDROID_COMPILE_SDK=28
ENV ANDROID_SDK_URL="https://dl.google.com/android/repository/sdk-tools-linux-3859397.zip" \
    ANDROID_HOME="/opt/android" \
    RUBY_MAJOR=2.2 \
    RUBY_VERSION=2.2.8 \
    RUBY_DOWNLOAD_SHA256=8f37b9d8538bf8e50ad098db2a716ea49585ad1601bbd347ef84ca0662d9268a \
    RUBYGEMS_VERSION=2.7.2 \
    TARGET_API="system-images;android-$ANDROID_COMPILE_SDK;default;x86_64" \
    TARGET_PLATFORM="platforms;android-$ANDROID_COMPILE_SDK" \
    AVD_NAME="integration-tests-$ANDROID_COMPILE_SDK"

ENV PATH $PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION

WORKDIR /opt

# Install Dependencies
COPY dependencies.txt /var/temp/dependencies.txt
RUN dpkg --add-architecture i386 && apt-get update
RUN apt-get install -y --allow-change-held-packages $(cat /var/temp/dependencies.txt)

# Install openjdk-8-jdk 
RUN apt-get update \
    && apt-get install -y openjdk-8-jdk \
    && apt-get autoremove -y \
    && apt-get clean

# Install ruby
RUN mkdir -p /usr/local/etc \
  	&& { \
  		echo 'install: --no-document'; \
  		echo 'update: --no-document'; \
  	} >> /usr/local/etc/gemrc

# some of ruby's build scripts are written in ruby so we purge this later to make sure our final image uses what we just built
RUN set -ex \
    && buildDeps='bison libgdbm-dev ruby' \
    && apt-get update \
    && apt-get install -y --no-install-recommends $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
    && wget --output-document=ruby.tar.gz --quiet http://cache.ruby-lang.org/pub/ruby/$RUBY_MAJOR/ruby-${RUBY_VERSION}.tar.gz \
    && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/src/ruby \
    && tar -xzf ruby.tar.gz -C /usr/src/ruby --strip-components=1 \
    && rm ruby.tar.gz \
    && cd /usr/src/ruby \
    && { echo '#define ENABLE_PATH_CHECK 0'; echo; cat file.c; } > file.c.new && mv file.c.new file.c \
    && autoconf \
    && ./configure --disable-install-doc \
    && make -j"$(nproc)" \
    && make install \
    && apt-get purge -y --auto-remove $buildDeps \
    && gem update --system $RUBYGEMS_VERSION \
    && rm -r /usr/src/ruby \
    && apt-get autoremove -y \
    && apt-get clean

# install things globally, for great justice and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_PATH="$GEM_HOME" \
  	BUNDLE_BIN="$GEM_HOME/bin" \
  	BUNDLE_SILENCE_ROOT_WARNING=1 \
  	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
	  && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

# Android SDKs
RUN mkdir android \
    && cd android \
    && wget -O tools.zip ${ANDROID_SDK_URL} \
    && unzip tools.zip && rm tools.zip \
    && chmod a+x -R $ANDROID_HOME \
    && chown -R root:root $ANDROID_HOME

# Pre-approved licenses << Might need to update regularly
RUN mkdir "${ANDROID_HOME}/licenses" || true \
    && echo -e "\nd56f5187479451eabf01fb78af6dfcb131a6481e" > "${ANDROID_HOME}/licenses/android-sdk-license" \
    && echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" > "${ANDROID_HOME}/licenses/android-sdk-preview-license" \
    && echo -e "\n601085b94cd77f0b54ff86406957099ebe79c4d6" > "${ANDROID_HOME}/licenses/android-googletv-license" \
    && echo -e "\n33b6a2b64607f11b759f320ef9dff4ae5c47d97a" > "${ANDROID_HOME}/licenses/google-gdk-license" \
    && echo -e "\nd975f751698a77b662f1254ddbeed3901e976f5a" > "${ANDROID_HOME}/licenses/intel-android-extra-license" \
    && echo -e "\ne9acab5b5fbb560a72cfaecce8946896ff6aab9d" > "${ANDROID_HOME}/licenses/mips-android-sysimage-license"

# Copy list of Android SDK packages to be installed
COPY android-packages.txt /var/temp/android-packages.txt

# Install SDK packages
RUN mkdir ~/.android \
    && touch ~/.android/repositories.cfg \
    && sdkmanager --package_file="/var/temp/android-packages.txt" --channel=0 --sdk_root="$ANDROID_HOME" --verbose \
    && sdkmanager $TARGET_API $TARGET_PLATFORM --verbose

# Create emulator
RUN echo "no" | avdmanager create avd --name $AVD_NAME --package $TARGET_API --force

# Cleaning
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && apt-get autoremove -y \
    && apt-get clean

# GO to workspace
RUN mkdir -p /opt/workspace
WORKDIR /opt/workspace
