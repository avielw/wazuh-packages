installElasticsearch() {

    logger "Installing Open Distro for Elasticsearch..."

    if [ ${sys_type} == "yum" ]; then
        eval "yum install opendistroforelasticsearch-${OD_VER}-${OD_REV} -y ${debug}"
    elif [ ${sys_type} == "zypper" ]; then
        eval "zypper -n install opendistroforelasticsearch=${OD_VER}-${OD_REV} ${debug}"
    elif [ ${sys_type} == "apt-get" ]; then
        eval "apt install elasticsearch-oss opendistroforelasticsearch -y ${debug}"
    fi

    if [  "$?" != 0  ]; then
        echo "Error: Elasticsearch installation failed"
        rollBack
        exit 1;  
    else
        elasticinstalled="1"
        logger "Done"      
    fi


}

configureElasticsearchAIO() {
 
    logger "Configuring Elasticsearch..."

    eval "curl -so /etc/elasticsearch/elasticsearch.yml ${resources}/open-distro/elasticsearch/7.x/elasticsearch_unattended.yml --max-time 300 ${debug}"
    eval "curl -so /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles.yml ${resources}/open-distro/elasticsearch/roles/roles.yml --max-time 300 ${debug}"
    eval "curl -so /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles_mapping.yml ${resources}/open-distro/elasticsearch/roles/roles_mapping.yml --max-time 300 ${debug}"
    eval "curl -so /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/internal_users.yml ${resources}/open-distro/elasticsearch/roles/internal_users.yml --max-time 300 ${debug}"        
    eval "rm /etc/elasticsearch/esnode-key.pem /etc/elasticsearch/esnode.pem /etc/elasticsearch/kirk-key.pem /etc/elasticsearch/kirk.pem /etc/elasticsearch/root-ca.pem -f ${debug}"

    ## Create certificates
    eval "mkdir /etc/elasticsearch/certs ${debug}"
    eval "cd /etc/elasticsearch/certs ${debug}"
    echo "${resources}/open-distro/tools/certificate-utility/wazuh-cert-tool.sh --max-time 300"
    eval "curl -so ~/wazuh-cert-tool.sh ${resources}/open-distro/tools/certificate-utility/wazuh-cert-tool.sh --max-time 300 ${debug}"

    export JAVA_HOME=/usr/share/elasticsearch/jdk/
        
    eval "cp ~/certs/elasticsearch* /etc/elasticsearch/certs/ ${debug}"
    eval "cp ~/certs/root-ca.pem /etc/elasticsearch/certs/ ${debug}"
    eval "cp ~/certs/admin* /etc/elasticsearch/certs/ ${debug}"
    
    # Configure JVM options for Elasticsearch
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    ram=$(( ${ram_gb} / 2 ))

    if [ ${ram} -eq "0" ]; then
        ram=1;
    fi    
    eval "sed -i "s/-Xms1g/-Xms${ram}g/" /etc/elasticsearch/jvm.options ${debug}"
    eval "sed -i "s/-Xmx1g/-Xmx${ram}g/" /etc/elasticsearch/jvm.options ${debug}"
  
    eval "/usr/share/elasticsearch/bin/elasticsearch-plugin remove opendistro-performance-analyzer ${debug}"
    # Start Elasticsearch
    startService "elasticsearch"
    echo "Initializing Elasticsearch..."
    until $(curl -XGET https://localhost:9200/ -uadmin:admin -k --max-time 120 --silent --output /dev/null); do
        echo -ne ${char}
        sleep 10
    done    

    eval "cd /usr/share/elasticsearch/plugins/opendistro_security/tools/ ${debug}"
    eval "./securityadmin.sh -cd ../securityconfig/ -icl -nhnv -cacert /etc/elasticsearch/certs/root-ca.pem -cert /etc/elasticsearch/certs/admin.pem -key /etc/elasticsearch/certs/admin-key.pem ${debug}"
    echo "Done"

}

configureElasticsearch() {
    logger "Configuring Elasticsearch..."

    eval "curl -so /etc/elasticsearch/elasticsearch.yml https://packages.wazuh.com/resources/${WAZUH_MAJOR}/open-distro/unattended-installation/distributed/templates/elasticsearch_unattended.yml --max-time 300 ${debug}"
    eval "curl -so /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles.yml https://packages.wazuh.com/resources/${WAZUH_MAJOR}/open-distro/elasticsearch/roles/roles.yml --max-time 300 ${debug}"
    eval "curl -so /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/roles_mapping.yml https://packages.wazuh.com/resources/${WAZUH_MAJOR}/open-distro/elasticsearch/roles/roles_mapping.yml --max-time 300 ${debug}"
    eval "curl -so /usr/share/elasticsearch/plugins/opendistro_security/securityconfig/internal_users.yml https://packages.wazuh.com/resources/${WAZUH_MAJOR}/open-distro/elasticsearch/roles/internal_users.yml --max-time 300 ${debug}"

    if [ -n "${single}" ]; then
        nh=$(awk -v RS='' '/network.host:/' ~/config.yml)
        nhr="network.host: "
        nip="${nh//$nhr}"
        echo "node.name: ${iname}" >> /etc/elasticsearch/elasticsearch.yml
        echo "${nn}" >> /etc/elasticsearch/elasticsearch.yml
        echo "${nh}" >> /etc/elasticsearch/elasticsearch.yml
        echo "cluster.initial_master_nodes: ${iname}" >> /etc/elasticsearch/elasticsearch.yml

        echo "opendistro_security.nodes_dn:" >> /etc/elasticsearch/elasticsearch.yml
        echo '        - CN='${iname}',OU=Docu,O=Wazuh,L=California,C=US' >> /etc/elasticsearch/elasticsearch.yml
    else
        echo "node.name: ${iname}" >> /etc/elasticsearch/elasticsearch.yml
        mn=$(awk -v RS='' '/cluster.initial_master_nodes:/' ~/config.yml)
        sh=$(awk -v RS='' '/discovery.seed_hosts:/' ~/config.yml)
        cn=$(awk -v RS='' '/cluster.name:/' ~/config.yml)
        echo "${cn}" >> /etc/elasticsearch/elasticsearch.yml
        mnr="cluster.initial_master_nodes:"
        rm="- "
        mn="${mn//$mnr}"
        mn="${mn//$rm}"

        shr="discovery.seed_hosts:"
        sh="${sh//$shr}"
        sh="${sh//$rm}"
        echo "cluster.initial_master_nodes:" >> /etc/elasticsearch/elasticsearch.yml
        for line in $mn; do
                IMN+=(${line})
                echo '        - "'${line}'"' >> /etc/elasticsearch/elasticsearch.yml
        done

        echo "discovery.seed_hosts:" >> /etc/elasticsearch/elasticsearch.yml
        for line in $sh; do
                DSH+=(${line})
                echo '        - "'${line}'"' >> /etc/elasticsearch/elasticsearch.yml
        done
        for i in "${!IMN[@]}"; do
            if [[ "${IMN[$i]}" = "${iname}" ]]; then
                pos="${i}";
            fi
        done
        if [[ ! " ${IMN[@]} " =~ " ${iname} " ]]; then
            echo "The name given does not appear on the configuration file"
            exit 1;
        fi
        nip="${DSH[pos]}"
        echo "network.host: ${nip}" >> /etc/elasticsearch/elasticsearch.yml

        echo "opendistro_security.nodes_dn:" >> /etc/elasticsearch/elasticsearch.yml
        for i in "${!IMN[@]}"; do
                echo '        - CN='${IMN[i]}',OU=Docu,O=Wazuh,L=California,C=US' >> /etc/elasticsearch/elasticsearch.yml
        done

    fi
    #awk -v RS='' '/## Elasticsearch/' ~/config.yml >> /etc/elasticsearch/elasticsearch.yml

    eval "rm /etc/elasticsearch/esnode-key.pem /etc/elasticsearch/esnode.pem /etc/elasticsearch/kirk-key.pem /etc/elasticsearch/kirk.pem /etc/elasticsearch/root-ca.pem -f ${debug}"
    eval "mkdir /etc/elasticsearch/certs ${debug}"
    eval "cd /etc/elasticsearch/certs ${debug}"


    # Configure JVM options for Elasticsearch
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    ram=$(( ${ram_gb} / 2 ))

    if [ ${ram} -eq "0" ]; then
        ram=1;
    fi
    eval "sed -i "s/-Xms1g/-Xms${ram}g/" /etc/elasticsearch/jvm.options ${debug}"
    eval "sed -i "s/-Xmx1g/-Xmx${ram}g/" /etc/elasticsearch/jvm.options ${debug}"

    jv=$(java -version 2>&1 | grep -o -m1 '1.8.0' )
    if [ "$jv" == "1.8.0" ]; then
        echo "root hard nproc 4096" >> /etc/security/limits.conf
        echo "root soft nproc 4096" >> /etc/security/limits.conf
        echo "elasticsearch hard nproc 4096" >> /etc/security/limits.conf
        echo "elasticsearch soft nproc 4096" >> /etc/security/limits.conf
        echo "bootstrap.system_call_filter: false" >> /etc/elasticsearch/elasticsearch.yml
    fi

    # Create certificates
    if [ -n "${single}" ]; then
        createCertificates name ip
    elif [ -n "${certificates}" ]; then
        createCertificates IMN DSH
    else
        logger "Done"
    fi

    if [ -n "${single}" ]; then
        copyCertificates iname
    else
        copyCertificates iname pos
    fi
    initializeElastic nip
    echo "Done"
}