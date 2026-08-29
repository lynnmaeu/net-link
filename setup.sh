#!/bin/bash
# Ensure script is run with sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (e.g., sudo bash setup.sh)"
  exit 1
fi

echo "Updating system..."
apt update && apt upgrade -y

echo "1. Configuring Static Ethernet Profile..."
nmcli connection add con-name static-eth0 ifname eth0 type ethernet ipv4.method manual ipv4.addresses 192.168.144.40/24 ipv4.gateway 192.168.144.1 ipv4.dns "192.168.144.1,8.8.8.8" ipv4.route-metric 50
nmcli connection up static-eth0

echo "2. Installing Nginx..."
apt install nginx -y

echo "3. Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "4. Installing and Configuring mavp2p..."
mkdir -p /home/pi/install_mavp2p && cd /home/pi/install_mavp2p
wget https://github.com/bluenviron/mavp2p/releases/download/v1.3.1/mavp2p_v1.3.1_linux_arm64v8.tar.gz
tar xvf mavp2p_v1.3.1_linux_arm64v8.tar.gz
mv mavp2p /usr/local/sbin

cat << 'EOF' > /home/pi/startmavlink.sh
#!/bin/bash
cd /home/pi
APIP=192.168.144.30
/usr/local/sbin/mavp2p --streamreq-disable --quiet tcpc:$APIP:5760 tcps:0.0.0.0:5760 udps:0.0.0.0:14550
EOF
chmod +x /home/pi/startmavlink.sh
chown pi:pi /home/pi/startmavlink.sh

cat << 'EOF' > /etc/systemd/system/mavlink.service
[Unit]
Description=MavP2P TCP MAVLink Stream
After=network-online.target tailscaled.service
Wants=network-online.target tailscaled.service
Requires=tailscaled.service

[Service]
Type=simple
ExecStart=/home/pi/startmavlink.sh
Restart=on-failure
User=pi
WorkingDirectory=/home/pi
ExecStartPre=/bin/sleep 10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mavlink.service

echo "5. Installing and Configuring MediaMTX..."
mkdir -p /home/pi/install_mediamtx && cd /home/pi/install_mediamtx
wget https://github.com/bluenviron/mediamtx/releases/download/v1.12.3/mediamtx_v1.12.3_linux_arm64.tar.gz
tar -xvzf mediamtx_v1.12.3_linux_arm64.tar.gz
mv mediamtx /usr/local/sbin/
mv mediamtx.yml /etc/

cat << 'EOF' >> /etc/mediamtx.yml
paths:
  siyi_a8_mini:
      source: rtsp://192.168.144.25:8554/main.264
      sourceProtocol: tcp
EOF

cat << 'EOF' > /etc/systemd/system/mediamtx.service
[Unit]
Description=MediaMTX RTSP Server
After=network.target

[Service]
ExecStart=/usr/local/sbin/mediamtx /etc/mediamtx.yml
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mediamtx.service

echo "================================================="
echo "Setup Complete!"
echo "IMPORTANT MANUAL STEP: Run 'sudo tailscale up' to authenticate the drone to your VPN network."
echo "Once authenticated, reboot the Pi."
echo "================================================="
