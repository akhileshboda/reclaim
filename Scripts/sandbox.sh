#!/usr/bin/env bash
# Throwaway test disks for Reclaim.
#
# Creates sparse disk images (at most 5 GB of declared capacity in total), attaches them as
# real volumes named RTEST-*, seeds them with realistic trash and junk fixtures, and tears
# everything down again. Nothing outside $RECLAIM_SANDBOX_DIR and /Volumes/RTEST-* is touched.
#
# Usage: Scripts/sandbox.sh up|seed|status|reset|detach|down
set -euo pipefail

SANDBOX_DIR="${RECLAIM_SANDBOX_DIR:-${TMPDIR:-/tmp}/reclaim-sandbox}"
mkdir -p "$SANDBOX_DIR"
SANDBOX_DIR="$(cd "$SANDBOX_DIR" && pwd -P)"
IMAGES="$SANDBOX_DIR/images"
DECOY="$SANDBOX_DIR/decoy-outside-volume"

MAX_TOTAL_MB=5120   # hard budget: 5 GB of declared capacity across all images
MIN_FREE_MB=10240   # refuse to run when the boot disk has less than 10 GB free

# name|filesystem|size in MB. Names stay <= 11 chars so they are valid FAT32 labels.
DISKS=(
  "RTEST-SSD|APFS|2048"
  "RTEST-USB|ExFAT|1536"
  "RTEST-CAM|MS-DOS FAT32|1024"
  "RTEST-HFS|HFS+|512"
)

die() { echo "sandbox: $*" >&2; exit 1; }
field() { echo "$1" | cut -d'|' -f"$2"; }

check_budget() {
  local total=0 d
  for d in "${DISKS[@]}"; do total=$((total + $(field "$d" 3))); done
  [ "$total" -le "$MAX_TOTAL_MB" ] || die "declared capacity ${total} MB exceeds the ${MAX_TOTAL_MB} MB budget"
  echo "$total"
}

check_free_space() {
  local free_mb
  free_mb=$(df -m / | awk 'NR==2 {print $4}')
  [ "$free_mb" -ge "$MIN_FREE_MB" ] || die "only ${free_mb} MB free on the boot disk; need ${MIN_FREE_MB} MB"
}

image_path() { echo "$IMAGES/$1.sparseimage"; }

# Prints the mount point of the volume attached from our image, or nothing.
mount_point_for() {
  local image
  image="$(image_path "$1")"
  hdiutil info | awk -v img="$image" '
    /^image-path/ { current = substr($0, index($0, ":") + 2) }
    /^\/dev\/disk/ && current == img && $NF ~ /^\/Volumes\// { print $NF }
  '
}

# Guards every write: the path must be one of our attached RTEST volumes.
assert_sandbox_volume() {
  local vol="$1" name="$2"
  [[ "$vol" == "/Volumes/$name" ]] || die "refusing to touch '$vol' (expected /Volumes/$name)"
  [[ "$name" == RTEST-* ]] || die "refusing to touch non-RTEST volume '$name'"
  [ "$(mount_point_for "$name")" == "$vol" ] || die "'$vol' is not attached from the sandbox image"
}

cmd_up() {
  check_budget >/dev/null
  check_free_space
  mkdir -p "$IMAGES"
  local d name fs size img mp
  for d in "${DISKS[@]}"; do
    name=$(field "$d" 1); fs=$(field "$d" 2); size=$(field "$d" 3); img=$(image_path "$name")
    if [ -e "/Volumes/$name" ] && [ -z "$(mount_point_for "$name")" ]; then
      die "/Volumes/$name exists but is not a sandbox image; refusing to continue"
    fi
    if [ ! -f "$img" ]; then
      hdiutil create -quiet -size "${size}m" -type SPARSE -fs "$fs" -volname "$name" "$img"
      echo "created  $name ($fs, ${size} MB max)"
    fi
    if [ -z "$(mount_point_for "$name")" ]; then
      hdiutil attach -quiet -noautoopen "$img"
    fi
    mp=$(mount_point_for "$name")
    [ -n "$mp" ] || die "failed to attach $name"
    echo "attached $name at $mp"
  done
}

write_file() { # path sizeMB
  dd if=/dev/zero of="$1" bs=1m count="$2" 2>/dev/null
}

# Real macOS junk starts with magic bytes; Reclaim checks them before deleting anything.
write_appledouble() { # path
  { printf '\000\005\026\007'; dd if=/dev/zero bs=4092 count=1 2>/dev/null; } > "$1"
}

write_dsstore() { # path
  { printf '\000\000\000\001Bud1'; dd if=/dev/zero bs=6136 count=1 2>/dev/null; } > "$1"
}

seed_volume() {
  local name="$1" vol="/Volumes/$1" uid trash i
  assert_sandbox_volume "$vol" "$name"
  uid=$(id -u)
  trash="$vol/.Trashes/$uid"
  mkdir -p "$trash"
  chmod 700 "$trash"

  # Data that must survive every cleanup.
  mkdir -p "$vol/Keep"
  echo "Reclaim sandbox: this file must never be deleted." > "$vol/Keep/important.txt"
  write_file "$vol/Keep/document.bin" 5

  case "$name" in
    RTEST-SSD)
      write_file "$trash/Interview_A-cam.mov" 300
      mkdir -p "$trash/Project Backup/Renders"
      for i in $(seq 1 40); do write_file "$trash/Project Backup/Renders/frame_$i.exr" 1; done
      echo "signed" > "$trash/Locked contract.pdf"
      chflags uchg "$trash/Locked contract.pdf"
      mkdir -p "$trash/Read-only folder"
      echo "x" > "$trash/Read-only folder/notes.txt"
      chmod 555 "$trash/Read-only folder"
      mkdir -p "$trash/Old Tool.app/Contents/MacOS"
      write_file "$trash/Old Tool.app/Contents/MacOS/Old Tool" 2
      ln -sfn "$DECOY" "$trash/Link outside volume"
      ln -sfn "$vol/Keep" "$trash/Link to Keep"
      ;;
    RTEST-USB)
      write_file "$trash/Holiday 2025.mp4" 200
      mkdir -p "$vol/Photos"
      for i in $(seq 1 20); do
        dd if=/dev/zero of="$vol/Photos/photo_$i.jpg" bs=1k count=100 2>/dev/null
        write_appledouble "$vol/Photos/._photo_$i.jpg"
      done
      write_dsstore "$vol/.DS_Store"
      write_dsstore "$vol/Photos/.DS_Store"
      # Decoys: junk-like names, user content. Must survive every cleanup.
      echo "My notes. Not an AppleDouble file." > "$vol/Photos/._notes-from-user.txt"
      echo "Not a Finder .DS_Store either." > "$vol/Keep/.DS_Store"
      mkdir -p "$vol/.TemporaryItems"
      echo "tmp" > "$vol/.TemporaryItems/folders.501"
      echo "<plist/>" > "$vol/.apdisk"
      ;;
    RTEST-CAM)
      write_file "$trash/DCIM_old.zip" 100
      mkdir -p "$vol/DCIM/100CANON"
      for i in $(seq 1 30); do
        dd if=/dev/zero of="$vol/DCIM/100CANON/IMG_$((1000 + i)).JPG" bs=1k count=200 2>/dev/null
        write_appledouble "$vol/DCIM/100CANON/._IMG_$((1000 + i)).JPG"
      done
      write_dsstore "$vol/DCIM/.DS_Store"
      ;;
    RTEST-HFS)
      write_file "$trash/Archive 2019.dmg" 50
      mkdir -p "$vol/Documents"
      write_dsstore "$vol/.DS_Store"
      write_dsstore "$vol/Documents/.DS_Store"
      ;;
  esac
  echo "seeded   $name"
}

cmd_seed() {
  mkdir -p "$DECOY"
  echo "Decoy outside every sandbox volume: a symlink in RTEST-SSD's trash points here. Must survive." > "$DECOY/must-survive.txt"
  local d
  for d in "${DISKS[@]}"; do seed_volume "$(field "$d" 1)"; done
}

cmd_status() {
  local total d name size img mp actual
  total=$(check_budget)
  printf '%-10s %-13s %8s %10s  %s\n' VOLUME FS MAX_MB ON_DISK MOUNT
  for d in "${DISKS[@]}"; do
    name=$(field "$d" 1); size=$(field "$d" 3); img=$(image_path "$name")
    actual="-"; [ -f "$img" ] && actual=$(du -h "$img" | cut -f1)
    mp=$(mount_point_for "$name"); [ -n "$mp" ] || mp="(not attached)"
    printf '%-10s %-13s %8s %10s  %s\n' "$name" "$(field "$d" 2)" "$size" "$actual" "$mp"
  done
  echo "declared total: ${total} MB (budget ${MAX_TOTAL_MB} MB)"
  [ -d "$IMAGES" ] && echo "actual disk use: $(du -sh "$IMAGES" | cut -f1) in $IMAGES"
}

cmd_detach() {
  local d name mp
  for d in "${DISKS[@]}"; do
    name=$(field "$d" 1); mp=$(mount_point_for "$name")
    if [ -n "$mp" ]; then hdiutil detach -quiet "$mp" || hdiutil detach -quiet -force "$mp"; echo "detached $name"; fi
  done
}

cmd_down() {
  cmd_detach
  local d
  for d in "${DISKS[@]}"; do rm -f "$(image_path "$(field "$d" 1)")"; done
  [ -d "$IMAGES" ] && rmdir "$IMAGES" 2>/dev/null || true
  rm -f "$DECOY/must-survive.txt"; [ -d "$DECOY" ] && rmdir "$DECOY" 2>/dev/null || true
  echo "sandbox images removed"
}

case "${1:-status}" in
  up) cmd_up ;;
  seed) cmd_seed ;;
  status) cmd_status ;;
  reset) cmd_down; cmd_up; cmd_seed ;;
  detach) cmd_detach ;;
  down) cmd_down ;;
  *) die "usage: $0 up|seed|status|reset|detach|down" ;;
esac
