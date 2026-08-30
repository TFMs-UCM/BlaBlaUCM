#!/usr/bin/env bash
# Cifrado en reposo de la base de datos (PostgreSQL) mediante LUKS/dm-crypt.
# Crea un disco cifrado, lo monta en /mnt/secure y prepara /mnt/secure/pgdata 
# para que Docker guarde ahi los datos de Postgres set -euo pipefail

DEVICE="${1:?Uso: setup_encrypted_volume.sh <dispositivo>  (p.ej. /dev/sdb)}"
MAPPER_NAME="pgcrypt"            # nombre del dispositivo desbloqueado
MOUNT_POINT="/mnt/secure"
KEYFILE="/root/.pgcrypt.key"    # clave para el desbloqueo automatico al arrancar

echo ">> Instalando cryptsetup..."
apt-get update -qq && apt-get install -y -qq cryptsetup

echo ">> Comprobando aceleracion AES por hardware (AES-NI)..."
if grep -qm1 aes /proc/cpuinfo; then
  echo "   OK: la CPU soporta AES-NI (sobrecoste de cifrado < 5%)."
else
  echo "   AVISO: sin AES-NI; el cifrado se hara por software (mas lento)."
fi

# Clave aleatoria de 4 K
echo ">> Generando clave en $KEYFILE ..."
if [[ ! -f "$KEYFILE" ]]; then
  dd if=/dev/urandom of="$KEYFILE" bs=1024 count=4 status=none
  chmod 0400 "$KEYFILE"
fi

# Formatear el disco como contenedor LUKS (AES-XTS, clave de 512 bits)
echo ">> Formateando $DEVICE como volumen LUKS (se borra su contenido)..."
cryptsetup luksFormat --type luks2 \
  --cipher aes-xts-plain64 --key-size 512 --hash sha256 \
  --batch-mode "$DEVICE" "$KEYFILE"

# Desbloquear el volumen
echo ">> Abriendo el volumen cifrado como /dev/mapper/$MAPPER_NAME ..."
cryptsetup open --key-file "$KEYFILE" "$DEVICE" "$MAPPER_NAME"

# Sistema de ficheros sobre el dispositivo ya descifrado
echo ">> Creando sistema de ficheros ext4..."
mkfs.ext4 -q "/dev/mapper/$MAPPER_NAME"

# Montar y crear el directorio de datos de Postgres
echo ">> Montando en $MOUNT_POINT ..."
mkdir -p "$MOUNT_POINT"
mount "/dev/mapper/$MAPPER_NAME" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/pgdata"
# UID/GID 999 = usuario postgres dentro de la imagen postgis oficial
chown -R 999:999 "$MOUNT_POINT/pgdata"

# Desbloqueo y montaje automaticos en cada arranque
echo ">> Configurando desbloqueo automatico (crypttab + fstab)..."
DEV_UUID="$(blkid -s UUID -o value "$DEVICE")"
grep -q "$MAPPER_NAME" /etc/crypttab 2>/dev/null || \
  echo "$MAPPER_NAME UUID=$DEV_UUID $KEYFILE luks" >> /etc/crypttab
grep -q "$MOUNT_POINT" /etc/fstab 2>/dev/null || \
  echo "/dev/mapper/$MAPPER_NAME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab

echo ""
echo "==========================================================================="
echo " Disco cifrado listo. Datos de Postgres -> $MOUNT_POINT/pgdata"
echo " En .env.docker anade:   PGDATA_HOST_PATH=$MOUNT_POINT/pgdata"
echo "==========================================================================="
