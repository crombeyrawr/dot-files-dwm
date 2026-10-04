#!/bin/bash
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

LOGFILE="$HOME/install.log"
exec > >(tee -a "$LOGFILE") 2>&1

log "=== Setup crombey dotfiles + tools ==="

# ───── pacman ─────
log "Atualizando sistema..."
sudo pacman -Syu --noconfirm

log "Instalando dependências..."
sudo pacman -S --needed --noconfirm \
    git base-devel unzip feh alacritty xclip flameshot curl wget \
    libx11 libxft libxinerama xorg-server xorg-xinit xorg-xrandr \
    nmap python-pip open-vm-tools jdk-openjdk picom

# ───── yay ─────
if ! command -v yay &>/dev/null; then
    log "Instalando yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm && cd ~
    rm -rf /tmp/yay
fi

# ───── fontes ─────
log "Instalando fontes..."
yay -S --noconfirm --needed ttf-zpix ttf-nerd-fonts-symbols

# ───── DWM ─────
log "Clonando dotfiles..."
[ -d ~/dwm-dotfiles ] && rm -rf ~/dwm-dotfiles
git clone https://github.com/h4rry1337/dwm-dotfiles ~/dwm-dotfiles
cd ~/dwm-dotfiles

mkdir -p ~/.config/alacritty ~/.wallpapers

# extrai zips
for file in bkp-*.zip; do
    unzip -qo "$file" 2>/dev/null || true
done

# garante pastas certas
[ -d dmenu-5.4 ] || warn "dmenu-5.4 nao encontrado, pulando"
[ -d dwm-6.6   ] || { warn "dwm-6.6 nao encontrado, abortando"; exit 1; }

# patch config.h: floating default + Alt como modifier
sed -i '43s/.*/\t{ "><>",      NULL },    \/* floating default *\//' dwm-6.6/config.h
sed -i '44s/.*/\t{ "[]=",      tile },    \/* tiling *\//' dwm-6.6/config.h
sed -i 's/Mod4Mask/Mod1Mask/g' dwm-6.6/config.h

# patch dwm.c: raise on click
sed -i 's/setfocus(c);/setfocus(c);\n\t\tXRaiseWindow(dpy, c->win);/' dwm-6.6/dwm.c

# patch dwm.c: sem focus on hover
sed -i 's/\[EnterNotify\] = enternotify,/[EnterNotify] = NULL,/' dwm-6.6/dwm.c

# compila
for dir in dwm-6.6 dmenu-5.4 slstatus; do
    [ -d "$dir" ] && (cd "$dir" && sudo make clean install && cd ..) || true
done

sudo mkdir -p /usr/share/xsessions
sudo cp dwm.desktop /usr/share/xsessions/
cp wallpaper-animefoda.jpg ~/.wallpapers/

# ───── alacritty ─────
log "Configurando alacritty..."
cat > ~/.config/alacritty/alacritty.toml << 'TOML'
[window]
opacity = 0.85
padding.x = 10
padding.y = 10

[colors.primary]
background = '#1a1a1a'
foreground = '#ffffff'

[font]
normal.family = "monospace"
size = 10.0

[cursor.style]
shape = "Underline"
blinking = "Off"
TOML

# ───── picom ─────
log "Configurando picom..."
mkdir -p ~/.config/picom
printf 'backend = "xrender";\nblur-method = "kernel";\nblur-kern = "3x3box";\nblur-background = true;\n' \
    > ~/.config/picom/picom.conf

# ───── startdwm ─────
log "Configurando startdwm..."
sudo tee /usr/local/bin/startdwm.sh > /dev/null << 'STARTDWM'
#!/bin/bash
OUTPUT=$(xrandr | grep " connected" | awk '{print $1}' | head -1)
xrandr --output "$OUTPUT" --mode 1366x768 2>/dev/null || true
slstatus &
feh --bg-scale ~/.wallpapers/wallpaper-animefoda.jpg &
picom --config ~/.config/picom/picom.conf &
vmware-user-suid-wrapper &
exec dwm
STARTDWM
sudo chmod 755 /usr/local/bin/startdwm.sh

echo "exec /usr/local/bin/startdwm.sh" > ~/.xinitrc

# ───── VMware Tools ─────
sudo systemctl enable --now vmtoolsd 2>/dev/null || true
sudo systemctl enable --now vmware-vmblock-fuse 2>/dev/null || true

# ───── ferramentas de segurança ─────
log "Instalando ferramentas..."

# impacket
sudo pip install impacket --break-system-packages 2>/dev/null || \
    warn "impacket: tente manualmente com pip install impacket"

# responder
if [ ! -d /opt/Responder ]; then
    sudo git clone https://github.com/lgandx/Responder /opt/Responder
fi
sudo ln -sf /opt/Responder/Responder.py /usr/local/bin/responder 2>/dev/null || true

# netexec
sudo pip install netexec --break-system-packages 2>/dev/null || \
    yay -S --noconfirm netexec 2>/dev/null || \
    warn "netexec: tente manualmente"

# chisel
log "Chisel..."
CHISEL_VER=$(curl -s https://api.github.com/repos/jpillora/chisel/releases/latest \
    | grep tag_name | cut -d'"' -f4)
wget -q "https://github.com/jpillora/chisel/releases/download/${CHISEL_VER}/chisel_${CHISEL_VER#v}_linux_amd64.gz" \
    -O /tmp/chisel.gz
gunzip -f /tmp/chisel.gz
sudo mv /tmp/chisel /usr/local/bin/chisel
sudo chmod +x /usr/local/bin/chisel

# ligolo-ng
log "Ligolo-ng..."
LIGOLO_VER=$(curl -s https://api.github.com/repos/nicocha30/ligolo-ng/releases/latest \
    | grep tag_name | cut -d'"' -f4)
wget -q "https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_agent_${LIGOLO_VER#v}_linux_amd64.tar.gz" \
    -O /tmp/ligolo-agent.tar.gz
wget -q "https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_proxy_${LIGOLO_VER#v}_linux_amd64.tar.gz" \
    -O /tmp/ligolo-proxy.tar.gz
sudo tar xf /tmp/ligolo-agent.tar.gz -C /usr/local/bin/
sudo tar xf /tmp/ligolo-proxy.tar.gz -C /usr/local/bin/

# bloodhound + neo4j
log "BloodHound..."
yay -S --noconfirm bloodhound neo4j 2>/dev/null || \
    warn "bloodhound: tente manualmente com yay -S bloodhound neo4j"

# mullvad
log "Mullvad..."
yay -S --noconfirm mullvad-vpn-bin 2>/dev/null || \
    warn "mullvad: tente manualmente com yay -S mullvad-vpn-bin"
sudo systemctl enable --now mullvad-daemon 2>/dev/null || true

# burp suite
log "Burp Suite..."
wget -q "https://portswigger.net/burp/releases/download?product=community&type=Jar" \
    -O ~/burpsuite.jar 2>/dev/null || \
    warn "Burp Suite: baixe manualmente em portswigger.net"
printf '#!/bin/bash\njava -jar ~/burpsuite.jar\n' | sudo tee /usr/local/bin/burpsuite > /dev/null
sudo chmod +x /usr/local/bin/burpsuite

log "=============================="
log "Concluido! Log: $LOGFILE"
log "Rode: startx"
log "=============================="
