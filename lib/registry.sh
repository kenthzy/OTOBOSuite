#!/usr/bin/env bash

_registry_register() {
	local ns="$1"
	shift
	local n="${ns}_NAMES" s="${ns}_STATUSES" m="${ns}_MESSAGES"
	eval "${n}+=(\"\$1\")"
	eval "${s}+=(\"\$2\")"
	eval "${m}+=(\"\$3\")"
}

_registry_has_fails() {
	local ns="$1"
	local s="${ns}_STATUSES"
	local -a arr
	eval "arr=(\"\${${s}[@]}\")"
	local v
	for v in "${arr[@]}"; do
		[[ "$v" == "FAIL" ]] && return 0
	done
	return 1
}

_registry_print_summary() {
	local ns="$1"
	local title="${2:-${ns} SUMMARY}"

	local n="${ns}_NAMES" s="${ns}_STATUSES" m="${ns}_MESSAGES"
	local -a names statuses messages
	eval "names=(\"\${${n}[@]}\")"
	eval "statuses=(\"\${${s}[@]}\")"
	eval "messages=(\"\${${m}[@]}\")"

	local pass=0 warn=0 fail=0 info=0 skip=0
	local v
	for v in "${statuses[@]}"; do
		case "$v" in PASS | OK) ((pass++)) ;; WARN) ((warn++)) ;;
		FAIL) ((fail++)) ;; INFO) ((info++)) ;; SKIP) ((skip++)) ;;
		esac
	done

	echo
	echo -e "${BOLD}============================================================${NC}"
	echo -e "${BOLD}$(printf '%*s' $(((30 - ${#title}) / 2)) "")${title}${NC}"
	echo -e "${BOLD}============================================================${NC}"

	local i f
	for i in "${!names[@]}"; do
		local st="${statuses[$i]}"
		case "$st" in
		PASS | OK) f="${GREEN}PASS${NC}" ;; WARN) f="${YELLOW}WARN${NC}" ;;
		FAIL) f="${RED}FAIL${NC}" ;; INFO) f="${LIGHT_BLUE}INFO${NC}" ;;
		SKIP) f="${MAGENTA}SKIP${NC}" ;;
		FIXED) f="${GREEN}FIXED${NC}" ;;
		esac
		printf " %-18s  %-4b  %s\n" "${names[$i]}" "$f" "${messages[$i]}"
	done

	echo -e "${BOLD}============================================================${NC}"
	local total=$((pass + warn + fail + info + skip))
	local r="Result: ${GREEN}${pass} PASS${NC}, ${YELLOW}${warn} WARN${NC}, ${RED}${fail} FAIL${NC}"
	r+=", ${LIGHT_BLUE}${info} INFO${NC}, ${MAGENTA}${skip} SKIP${NC} (${total} total)"
	echo -e " ${r}"
	echo -e "${BOLD}============================================================${NC}"
	echo
}
