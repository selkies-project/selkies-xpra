FROM ubuntu:20.04

# Add Tini
ARG TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64 /tini
RUN chmod +x /tini

# Configure locale
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        locales \
        locales-all

RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

# Copy dev scripts
ENV DEV_SCRIPTS_DIR /usr/share/dev-scripts
WORKDIR ${DEV_SCRIPTS_DIR}
COPY config/ ./

# Copy customization
COPY customize/ ./customize/

# Install all customization
RUN for f in $(find . -iname "*.customize.sh" | sort); do echo "INFO: Installing customizations: $f"; bash -ex $f; done

# Set environment variables
ENV DISPLAY :0
ENV SDL_AUDIODRIVER pulse
ENV PATH ${PATH}:/usr/games

# Create the user
RUN groupadd --gid 1000 user && \
    adduser --uid 1000 --gid 1000 --disabled-password --gecos '' user

# Set permissions on the desktop shortcuts
RUN chown -R 1000:1000 /etc/skel/Desktop && \
    chmod +x /etc/skel/Desktop/*

WORKDIR /home/user/project

RUN chown -R user:user /home/user

# Grant sudo to user for vulkan init workaround
RUN adduser user sudo
RUN echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

# Switch to user
USER user

# Use bash as default shell
ENV SHELL /bin/bash
ENV USER user
ENV DISPLAY :0

ENV XPRA_ENTRYPOINT=/usr/share/dev-scripts/xpra_desktop_entrypoint.sh

# Note that Spaces pod template will enforce entrypoint.
ENTRYPOINT ["/tini", "--", "/usr/share/dev-scripts/desktop_entrypoint.sh"]
