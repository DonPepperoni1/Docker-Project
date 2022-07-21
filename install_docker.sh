#!/usr/bin/env bash

function printHelp() {
    echo "USAGE :   ./docker_install.sh [-h] [-i] [-c]"
    echo "          -h          Print this help message"
    echo "          -i          install docker"
    echo "          -d          clean la conf existante"
}

function install_docker() {
    sudo apt update
    sudo apt install -y docker.io
    sudo systemctl enable docker --now
    sudo docker --version
    sudo group add docker
    sudo usermod -aG docker $USER
    printf '%s\n' "deb https://download.docker.com/linux/debian bullseye stable" | sudo tee /etc/apt/sources.list.d/docker-ce.list
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker-ce-archive-keyring.gpg
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    REQUIRED_DOCKER_PKG="docker.io docker docker-ce docker-ce-cli containerd.io"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_DOCKER_PKG| grep "REQUIRED_DOCKER_PKG="docker.io docker docker-ce docker-ce-cli containerd.io"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_DOCKER_PKG| grep "install ok installed")
    echo Checking for $REQUIRED_DOCKER_PKG: $PKG_OK
    if [ "" ?? "$PKG_DOCKER_OK" ]; then
    echo "No $REQUIRED_DOCKER_PKG. Setting up $REQUIRED_DOCKER_PKG."
    sudo apt-get --yes install $REQUIRED_DOCKER_PKG 
    fi")
    echo "Checking for $REQUIRED_DOCKER_PKG: $PKG_OK"
    if [ "" = "$PKG_OK" ]; then
        echo "No $REQUIRED_DOCKER_PKG. Setting up $REQUIRED_DOCKER_PKG."
        sudo apt-get --yes install $REQUIRED_DOCKER_PKG 
    fi

# On télécharge l'image nginx-unprivileged des dépots officiels nginxinx sur github et on rend les scripts exécutables.
    echo -e "[+] - Script pour mettre les containers en écoute en IPv6 par défaut"
    echo ""
    wget https://raw.githubusercontent.com/nginxinc/docker-nginx-unprivileged/main/stable/alpine/10-listen-on-ipv6-by-default.sh
    sudo chmod +x 10-listen-on-ipv6-by-default.sh # rendre le script exécutable

    echo -e "[+] - Script docker rootless"
    wget https://get.docker.com/rootless
    mv rootless rootless.sh
    sudo chmod +x rootless.sh

    echo -e "[+] - Script envsubst"
    echo ""
    wget https://raw.githubusercontent.com/nginxinc/docker-nginx-unprivileged/main/stable/alpine/20-envsubst-on-templates.sh
    sudo chmod +x 20-envsubst-on-templates.sh

    echo -e "[+] - Script Tune worker processes"
    echo ""
    wget https://raw.githubusercontent.com/nginxinc/docker-nginx-unprivileged/main/stable/alpine/30-tune-worker-processes.sh
    sudo chmod +x 30-tune-worker-processes.sh

    echo -e "[+] - Script entrypoint pour le lancement du conteneur"
    echo ""
    wget https://raw.githubusercontent.com/nginxinc/docker-nginx-unprivileged/main/stable/alpine/docker-entrypoint.sh
    sudo chmod +x docker-entrypoint.sh

    echo -e "[+] - On télécharge le Dockerfile" # permettra de créer une image alpine avec nginx et tout le nécessaire"
    echo ""
    wget https://raw.githubusercontent.com/nginxinc/docker-nginx-unprivileged/main/stable/alpine/Dockerfile

    echo -e "[+] - Installation de docker-compose"
    echo ""
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose # on le rend exécutable
    docker-compose --version

    echo -e "[+] - Installation d'Harbor"
    echo ""
    wget https://github.com/goharbor/harbor/releases/download/v2.5.0/harbor-online-installer-v2.5.0.tgz

    if [ -f $SCRIPTS ] && [ -f $SCRIPTS2 ]; then
        echo "$SCRIPTS $SCRIPTS2 Les fichiers existent."

    else 
        echo "$SCRIPTS $SCRIPTS2 non existant."
        exit 1
    fi

    docker build -t docker-nginx-unprivileged:latest .

    # On créé un bridge pour séparer le conteneur dans un autre réseau :
    docker network create --driver=bridge --subnet=10.0.0.0/24 custom-ng-net

    # On lance le conteneur en tâche de fond, On lui assigne le port => 0.0.0.0:8080->80/tcp, :::8080->80/tcp in custom-ng-net
    docker run -d -p 8080:80 --cap-drop=all \
    --cap-add=chown --cap-add=dac_override \
    --cap-add=setgid --cap-add=setuid \
    --cap-add=net_bind_service \
    --network="custom-ng-net" docker-nginx-unprivileged
    # On lui donne uniquement les capabilities dont il a besoin
    # cap-add=chown -> capability pour changer le propriétaire d’un fichier
    # cap-add=setgid -> capability pour de changer le GID
    # cap-add=net_bind_service -> capability pour écouter sur un port inférieur à 1024
    # network="custom-ng-net" docker-nginx-unprivileged charge la conf bridge faite auparavant

    # Ouvre firefox à la page index d'nginx
    firefox 0.0.0.0:80 >/dev/null 2>&1 & disown

    tar xzvf harbor-online-installer-v2.5.0.tgz # Décompression du tgz d'Harbor
    sudo rm harbor-online-installer-v2.5.0.tgz # suppression du tgz
    cp ./harbor.yml ./harbor/ # copie le yml Harbor qu'on a créé voir harbor.yml dans le répertoire d'Harbor
    cd ./harbor # ouverture du répertoire Harbor
    # voir https://docs.docker.com/registry/insecure/
    echo '{"insecure-registries" : ["10.0.2.15:8080", "10.0.2.15"]}' | sudo tee /etc/docker/deamon.json
    sudo ./install.sh --with-trivy # Install script with trivy avec harbor
    echo ""
    echo "Terminé"

    # Open browser to Harbor login page
    firefox http://10.0.2.15:8080 >/dev/null 2>&1 & disown
    clear
    echo "Job Done"
}

function delete() {
    docker kill $(docker ps -q) # on kill le process docker
    docker network rm custom-ng-net  # On supprime la carte brigde
    sudo rm -rf harbor # on supprime le répertoire de l'app harbor
    sudo apt-get purge docker.io docker-ce docker-ce-cli containerd.io -y
    SCRIPTS="10-listen-on-ipv6-by-default.sh rootless.sh 20-envsubst-on-templates.sh"
    SCRIPTS2= "30-tune-worker-processes.sh Dockerfile docker-entrypoint.sh"
    if [ -f $SCRIPTS ] && [ -f $SCRIPTS2 ]; then
        echo "$SCRIPTS $SCRIPTS2 Les fichiers existent."
        rm $SCRIPTS $SCRIPTS2
        echo "Nettoyé"
    else 
        echo "$SCRIPTS $SCRIPTS2 non existants."
    fi
    clear
    echo "Job Done"
}

#if [ $EUID != 0 ]; then
#    sudo "$0" "$@"
#    exit $?
#fi

if [ $# = 0 ] || [ $1 = "-h" ]; then
    printHelp

elif [ $1 = "-i" ]; then
    install_docker

elif [ $1 = "-d" ]; then
    delete
fi