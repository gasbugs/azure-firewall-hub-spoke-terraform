#!/usr/bin/env bash
# Run on either spoke VM: bash test-connectivity.sh <other-vm-private-ip>
# No apt install or broad egress rules are required.
set -uo pipefail
peer="${1:?Supply the other spoke VM private IP}"
failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
for tool in python3 curl ping; do
  command -v "$tool" >/dev/null || { printf 'Missing required command: %s\n' "$tool"; exit 2; }
done

. /etc/os-release
printf 'VM=%s OS=%s peer=%s\n' "$(hostname)" "$PRETTY_NAME" "$peer"
resolvectl dns 2>/dev/null || true

if python3 - <<'PY'
import socket, struct
packet = struct.pack('!HHHHHH', 0x7654, 0x0100, 1, 0, 0, 0) + b'\x05naver\x03com\x00\x00\x01\x00\x01'
def check(reply):
    tx, flags, questions, answers, _, _ = struct.unpack('!HHHHHH', reply[:12])
    assert tx == 0x7654 and flags & 0x8000 and flags & 15 == 0 and answers > 0
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.settimeout(8)
    s.sendto(packet, ('8.8.8.8', 53))
    check(s.recvfrom(4096)[0])
with socket.create_connection(('8.8.8.8', 53), timeout=8) as s:
    s.sendall(struct.pack('!H', len(packet)) + packet)
    def read_exact(n):
        data = b''
        while len(data) < n:
            chunk = s.recv(n - len(data))
            if not chunk: raise RuntimeError('Unexpected DNS EOF')
            data += chunk
        return data
    check(read_exact(struct.unpack('!H', read_exact(2))[0]))
print('System resolver:', sorted({r[4][0] for r in socket.getaddrinfo('naver.com', 80, socket.AF_INET)}))
PY
then pass 'DNS UDP/TCP 53 to 8.8.8.8 and system name resolution'; else fail 'DNS'; fi

if ping -c 3 -W 3 "$peer"; then pass 'ICMP to opposite spoke through firewall'; else fail 'cross-spoke ICMP'; fi

for domain in naver.com www.naver.com; do
  code=$(curl --noproxy '*' --connect-timeout 8 --max-time 15 -sS -o /dev/null -w '%{http_code}' "http://$domain")
  case "$code" in
    2??|3??) pass "HTTP $domain returned $code (redirect deliberately not followed)" ;;
    *) fail "HTTP $domain returned $code" ;;
  esac
done

body=$(mktemp)
trap 'rm -f "$body"' EXIT
code=$(curl --noproxy '*' --connect-timeout 8 --max-time 15 -sS -o "$body" -w '%{http_code}' http://example.com)
if [[ "$code" == 470 ]] && grep -qi 'deny\|denied' "$body"; then
  pass 'Unlisted HTTP domain denied by Azure Firewall'
else
  fail "Expected Azure Firewall HTTP denial for example.com, received $code"
fi

if curl --noproxy '*' --connect-timeout 5 --max-time 8 -sS -o /dev/null https://naver.com; then
  fail 'HTTPS unexpectedly allowed'
else
  pass 'HTTPS denied (HTTP-only policy)'
fi

if python3 - "$peer" <<'PY'
import socket, sys
for name, target in [('unapproved DNS TCP', ('1.1.1.1', 53)), ('cross-spoke SSH', (sys.argv[1], 22))]:
    try:
        with socket.create_connection(target, timeout=5):
            print('Unexpected connection:', name)
            sys.exit(1)
    except (TimeoutError, ConnectionRefusedError):
        print('Blocked:', name)
PY
then pass 'Unapproved DNS and cross-spoke SSH blocked'; else fail 'Unexpected TCP egress'; fi

if ping -c 1 -W 2 8.8.8.8; then
  fail 'Unexpected Internet ICMP success; investigate a routing bypass'
else
  pass 'Internet ICMP unavailable as documented; not an acceptance requirement'
fi
printf 'RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
