#!/bin/bash

[[ ${DEBUG} = "yes" ]] && set -ex || set -e

# Edit system configuration
systemConfig() {

  echo "Upgrading the system. This may take a while ..."
  yum upgrade -y > /dev/null 2>&1

  # Disable kernel messages and edit background
  mv ${CUSTOM_PATH}/grub/wazuh.png /boot/grub2/
  mv ${CUSTOM_PATH}/grub/grub /etc/default/
  grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1

  # Update Wazuh indexer jvm heap
  mv ${CUSTOM_PATH}/automatic_set_ram.sh /etc/
  chmod 755 /etc/automatic_set_ram.sh
  mv ${CUSTOM_PATH}/updateIndexerHeap.service /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable updateIndexerHeap.service

  # Change root password (root:wazuh)
  sed -i "s/root:.*:/root:\$1\$pNjjEA7K\$USjdNwjfh7A\.vHCf8suK41::0:99999:7:::/g" /etc/shadow

  # Add custom user ($1$pNjjEA7K$USjdNwjfh7A.vHCf8suK41 -> wazuh)
  adduser ${SYSTEM_USER}
  sed -i "s/${SYSTEM_USER}:!!/${SYSTEM_USER}:\$1\$pNjjEA7K\$USjdNwjfh7A\.vHCf8suK41/g" /etc/shadow

  gpasswd -a ${SYSTEM_USER} wheel
  hostname ${HOSTNAME}

  # AWS instance has this enabled
  sed -i "s/PermitRootLogin yes/#PermitRootLogin yes/g" /etc/ssh/sshd_config

  # SSH configuration
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
  echo "PermitRootLogin no" >> /etc/ssh/sshd_config

  # Edit system custom welcome messages
  bash ${CUSTOM_PATH}/messages.sh ${DEBUG} ${WAZUH_VERSION} ${SYSTEM_USER}

  # Install dependencies
  yum install -y libnss3.so xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi xorg-x11-utils xorg-x11-fonts-cyrillic xorg-x11-fonts-Type1 xorg-x11-fonts-misc fontconfig freetype ipa-gothic-fonts

}

# Edit unattended installer
preInstall() {

  # Set debug mode
  if [ "${DEBUG}" == "yes" ]; then
    sed -i "s/\#\!\/bin\/bash/\#\!\/bin\/bash\nset -x/g" ${UNATTENDED_PATH}/${INSTALLER}
  fi

  # Change repository if dev is specified
  if [ "${PACKAGES_REPOSITORY}" = "dev" ]; then
    sed -i "s/packages\.wazuh\.com/packages-dev\.wazuh\.com/g" ${UNATTENDED_PATH}/${INSTALLER} 
    sed -i "s/packages-dev\.wazuh\.com\/4\.x/packages-dev\.wazuh\.com\/pre-release/g" ${UNATTENDED_PATH}/${INSTALLER} 
  fi

  # Remove kibana admin user
  PATTERN="eval \"rm \/etc\/elasticsearch\/e"
  FILE_PATH="\/usr\/share\/elasticsearch\/plugins\/opendistro_security\/securityconfig"
  sed -i "s/${PATTERN}/sed -i \'\/^admin:\/,\/admin user\\\\\"\/d\' ${FILE_PATH}\/internal_users\.yml\n        ${PATTERN}/g" ${UNATTENDED_PATH}/${INSTALLER}
 
  # Change user:password in curls
  sed -i "s/admin:admin/wazuh:wazuh/g" ${UNATTENDED_PATH}/${INSTALLER}

  # Replace admin/admin for wazuh/wazuh in filebeat.yml
  PATTERN="eval \"curl -so \/etc\/filebeat\/wazuh-template"
  sed -i "s/${PATTERN}/sed -i \"s\/admin\/wazuh\/g\" \/etc\/filebeat\/filebeat\.yml\n        ${PATTERN}/g" ${UNATTENDED_PATH}/${INSTALLER}

  # Disable start of wazuh-manager
  sed -i "s/startService \"wazuh-manager\"/\#startService \"wazuh-manager\"/g" ${UNATTENDED_PATH}/${INSTALLER}

  # Disable passwords change
  sed -i "s/wazuhpass=/#wazuhpass=/g" ${UNATTENDED_PATH}/${INSTALLER}
  sed -i "s/changePasswords$/#changePasswords\nwazuhpass=\"wazuh\"/g" ${UNATTENDED_PATH}/${INSTALLER}
  sed -i "s/ra=/#ra=/g" ${UNATTENDED_PATH}/${INSTALLER}

  # Revert url to packages.wazuh.com to get filebeat gz
  sed -i "s/'\${repobaseurl}'\/filebeat/https:\/\/packages.wazuh.com\/4.x\/filebeat/g" ${UNATTENDED_PATH}/${INSTALLER}

}

# Edit wazuh installation
postInstall() {

  # Change Wazuh repo dev to prod
  if [ "${PACKAGES_REPOSITORY}" = "dev" ]; then
    sed -i "s/-dev//g" /etc/yum.repos.d/wazuh.repo
    sed -i "s/pre-release/4.x/g" /etc/yum.repos.d/wazuh.repo
  fi

  # Edit window title
  sed -i "s/null, \"Elastic\"/null, \"Wazuh\"/g" /usr/share/kibana/src/core/server/rendering/views/template.js

  curl -so ${CUSTOM_PATH}/custom_welcome.tar.gz https://wazuh-demo.s3-us-west-1.amazonaws.com/custom_welcome_opendistro_docker.tar.gz
  tar -xf ${CUSTOM_PATH}/custom_welcome.tar.gz -C ${CUSTOM_PATH}
  cp ${CUSTOM_PATH}/custom_welcome/wazuh_logo_circle.svg /usr/share/kibana/src/core/server/core_app/assets/
  cp ${CUSTOM_PATH}/custom_welcome/wazuh_wazuh_bg.svg /usr/share/kibana/src/core/server/core_app/assets/
  cp ${CUSTOM_PATH}/custom_welcome/template.js.hbs /usr/share/kibana/src/legacy/ui/ui_render/bootstrap/template.js.hbs

  # Add custom css in kibana
  less ${CUSTOM_PATH}/customWelcomeKibana.css >> /usr/share/kibana/src/core/server/core_app/assets/legacy_light_theme.css

}

clean() {

  rm -f /securityadmin_demo.sh
  yum clean all

}
