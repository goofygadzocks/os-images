# =============================================================================
# os-images: bootc images for cruncher, watcher (:virt) and the Dumper VM
# (:dumper), derived from Fedora Silverblue.
#
# Fedora version bump (e.g. F45 in Oct 2026): change the FROM tag below and,
# if pinned anywhere else, nothing — RPM Fusion URLs use $(rpm -E %fedora).
# =============================================================================

FROM quay.io/fedora/fedora-silverblue:44 AS common

# --- Third-party repos shared by all variants --------------------------------
RUN curl -fsSL https://repo.vivaldi.com/archive/vivaldi-fedora.repo \
      -o /etc/yum.repos.d/vivaldi.repo

# --- Packages shared by all variants -----------------------------------------
RUN rm /opt && mkdir /opt && \
    dnf install -y \
      iotop \
      lm_sensors \
      rasdaemon \
      vivaldi-stable && \
    dnf clean all && \
    mv /opt/vivaldi /usr/lib/vivaldi && \
    rmdir /opt && \
    ln -s var/opt /opt && \
    printf 'L /opt/vivaldi - - - - /usr/lib/vivaldi\n' > /usr/lib/tmpfiles.d/vivaldi.conf && \
    systemctl enable rasdaemon.service

# --- Shared config -----------------------------------------------------------
# common/etc: sensors.d mappings, polkit rules, anything else that should be
# a default on every machine. Note: files here become *image defaults*; any
# pre-existing local copy of the same path in a machine's /etc wins the 3-way
# merge until deleted locally.
COPY common/etc/ /etc/
# cosign public key + verification policy so bootc verifies all future updates
COPY common/pki/ /etc/pki/containers/
COPY common/containers/ /etc/containers/

# =============================================================================
# virt — cruncher + watcher: libvirt/KVM hosts, bridged VLAN networking only
# =============================================================================
FROM common AS virt

RUN dnf install -y \
      virt-install \
      virt-manager \
      virt-viewer && \
    dnf remove -y libvirt-daemon-config-network && \
    dnf clean all

# Hardware H.264 via VA-API on AMD (RDP-into-host GRD encode, Vivaldi decode).
# Not currently needed — always at the console; software encode is fine as a
# fallback. Uncomment to enable:
# RUN dnf install -y \
#       https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
#       https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
#     dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld && \
#     dnf clean all

# Bridged libvirt networks (br9 / br22) + autostart. Bridges themselves are
# per-host NetworkManager state configured once locally, not baked here.
COPY virt/etc/libvirt/ /etc/libvirt/

RUN bootc container lint

# =============================================================================
# dumper — recorder/reviewer VM on watcher: no libvirt, stock networking,
# Panther Lake SR-IOV VF media stack
# =============================================================================
FROM common AS dumper

RUN dnf install -y \
      https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    dnf install -y \
      intel-media-driver \
      libavcodec-freeworld \
      libva-utils && \
    dnf clean all

RUN bootc container lint
