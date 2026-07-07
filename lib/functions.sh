#!/usr/bin/env bash

info() {

echo -e "${LIGHT_BLUE}[INFO]${NC} $1"

}

success() {

echo -e "${GREEN}[ OK ]${NC} $1"

}

warning() {

echo -e "${YELLOW}[WARN]${NC} $1"

}

error() {

echo -e "${RED}[FAIL]${NC} $1"

exit 1

}

line() {

echo "------------------------------------------------------------"

}
