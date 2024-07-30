#
# SPDX-FileCopyrightText: 2024 The Evolution X Project
#
# SPDX-License-Identifier: Apache-2.0
#

#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
ENDCOLOR='\033[0m'

display_header() {
    echo -e "${GREEN}===========================================================${ENDCOLOR}"
    echo -e "${BLUE}      ______            __      __  _                _  __  ${ENDCOLOR}"
    echo -e "${BLUE}     / ____/   ______  / /_  __/ /_(_)___  ____     | |/ /  ${ENDCOLOR}"
    echo -e "${BLUE}    / __/ | | / / __ \/ / / / / __/ / __ \/ __ \    |   /   ${ENDCOLOR}"
    echo -e "${BLUE}   / /___ | |/ / /_/ / / /_/ / /_/ / /_/ / / / /   /   |    ${ENDCOLOR}"
    echo -e "${BLUE}  /_____/ |___/\____/_/\__,_/\__/_/\____/_/ /_/   /_/|_|    ${ENDCOLOR}"
    echo -e "${BLUE}                                                            ${ENDCOLOR}"
    echo -e "${BLUE}                    Private key generator                   ${ENDCOLOR}"
    echo -e "${BLUE}                                                            ${ENDCOLOR}"
    echo -e "${BLUE}                        #KeepEvolving                       ${ENDCOLOR}"
    echo -e "${GREEN}===========================================================${ENDCOLOR}"
}

check_dir() {
    if [[ -z "$ANDROID_BUILD_TOP" ]]; then
        echo -e "${RED}ANDROID_BUILD_TOP is not set. Please run '. build/envsetup.sh' from the root of the source tree before running this script.${ENDCOLOR}"
        exit 1
    fi

    if [[ "$(pwd)" != "${ANDROID_BUILD_TOP}/vendor/lineage-priv/keys" ]]; then
        echo -e "${RED}This must be run from ${ANDROID_BUILD_TOP}/vendor/lineage-priv/keys!${ENDCOLOR}"
        echo -e "${RED}Current directory is $(pwd)!${ENDCOLOR}"
        exit 1
    fi
}

get_target_certificates() {
    local cert_file="certificates.txt"
    local apex_cert_file="apex_certificates.txt"

    if [[ -f "$cert_file" ]]; then
        mapfile -t certificates < "$cert_file"
    else
        echo -e "${RED}$cert_file not found!${ENDCOLOR}"
        exit 1
    fi

    if [[ -f "$apex_cert_file" ]]; then
        mapfile -t apex_certificates < "$apex_cert_file"
    else
        echo -e "${RED}$apex_cert_file not found!${ENDCOLOR}"
        exit 1
    fi
}

confirm() {
    while true; do
        read -r -p "$1 (yes/no): " input
        case "$input" in
            [yY][eE][sS]|[yY]) echo "yes"; return ;;
            [nN][oO]|[nN]) echo "no"; return ;;
            *) ;;
        esac
    done
}

prompt_key_size() {
    while true; do
        read -p "$1" input
        if [[ "$input" == "2048" || "$input" == "4096" ]]; then
            echo "$input"
            break
        fi
    done
}

prompt() {
    while true; do
        read -p "$1" input
        if [[ -n "$input" ]]; then
            echo "$input"
            break
        fi
    done
}

user_input() {
    if [[ $(confirm "Do you want to customize the key size and subject?") == "yes" ]]; then
        key_size=$(prompt_key_size "Enter the key size (2048 or 4096, APEX will always use 4096): ")
        country_code=$(prompt "Enter the country code (e.g., US): ")
        state=$(prompt "Enter the state or province (e.g., California): ")
        city=$(prompt "Enter the city or locality (e.g., Mountain View): ")
        org=$(prompt "Enter the organization (e.g., Android): ")
        ou=$(prompt "Enter the organizational unit (e.g., Android): ")
        cn=$(prompt "Enter the common name (e.g., Android): ")
        email=$(prompt "Enter the email address (e.g., android@android.com): ")

        echo -e "${BLUE}Subject information to be used:${ENDCOLOR}"
        echo "Key Size: $key_size"
        echo "Country Code: $country_code"
        echo "State/Province: $state"
        echo "City/Locality: $city"
        echo "Organization (O): $org"
        echo "Organizational Unit (OU): $ou"
        echo "Common Name (CN): $cn"
        echo "Email Address: $email"

        if [[ $(confirm "Is this information correct?") != "yes" ]]; then
            echo -e "${RED}Generation aborted!${ENDCOLOR}"
            exit 1
        fi
    else
        key_size='2048'
        country_code='US'
        state='California'
        city='Mountain View'
        org='Android'
        ou='Android'
        cn='Android'
        email='android@android.com'
    fi

    subject="/C=$country_code/ST=$state/L=$city/O=$org/OU=$ou/CN=$cn/emailAddress=$email"
}

generate_certificates() {
    echo -e "${BLUE}Generating certificates...${ENDCOLOR}"
    local generated=false

    for certificate in "${certificates[@]}" "${apex_certificates[@]}"; do
        if [[ (-f "${certificate}.x509.pem" && -f "${certificate}.pk8") ||
              (-f "${certificate}.certificate.override.x509.pem" && -f "${certificate}.certificate.override.pk8") ]]; then
            continue
        else
            generated=true
            if [[ " ${certificates[*]} " == *" $certificate "* ]]; then
                size=$key_size
            else
                size=4096
                certificate="$certificate.certificate.override"
            fi
            echo | bash <(sed "s/2048/$size/" ../../../development/tools/make_key) \
                "$certificate" \
                "$subject"
        fi
    done

    if ! $generated; then
        echo -e "${GREEN}No new keys were generated. Exiting...${ENDCOLOR}"
        exit 0
    fi
}

create_symlinks() {
    echo -e "${BLUE}Creating system links...${ENDCOLOR}"
    rm -f BUILD.bazel releasekey.pk8 releasekey.x509.pem
    ln -sf ../../../build/make/target/product/security/BUILD.bazel BUILD.bazel
    ln -sf testkey.pk8 releasekey.pk8
    ln -sf testkey.x509.pem releasekey.x509.pem
}

generate_android_bp() {
    echo -e "${BLUE}Generating Android.bp...${ENDCOLOR}"
    rm -f Android.bp
    for apex_certificate in "${apex_certificates[@]}"; do
        echo "android_app_certificate {" >> Android.bp
        echo "    name: \"$apex_certificate.certificate.override\"," >> Android.bp
        echo "    certificate: \"$apex_certificate.certificate.override\"," >> Android.bp
        echo "}" >> Android.bp
        if [[ $apex_certificate != "${apex_certificates[-1]}" ]]; then
            echo >> Android.bp
        fi
    done
}

generate_keys_mk() {
    echo -e "${BLUE}Generating keys.mk...${ENDCOLOR}"
    rm -f keys.mk
    echo "PRODUCT_CERTIFICATE_OVERRIDES := \\" > keys.mk
    for apex_certificate in "${apex_certificates[@]}"; do
        if [[ $apex_certificate != "${apex_certificates[-1]}" ]]; then
            echo "    ${apex_certificate}:${apex_certificate}.certificate.override \\" >> keys.mk
        else
            echo "    ${apex_certificate}:${apex_certificate}.certificate.override" >> keys.mk
        fi
    done

    echo >> keys.mk
    echo "PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/testkey" >> keys.mk
    echo "PRODUCT_EXTRA_RECOVERY_KEYS :=" >> keys.mk
}

display_header
check_dir
get_target_certificates
user_input
generate_certificates
create_symlinks
generate_android_bp
generate_keys_mk
