---
name: plan9port-cluster
description: Shared network storage and CPU offload for an AI agent swarm, built on plan9port (fossil + venti over 9P). Use when a job is too heavy for this machine, when agents on different machines must share files, or when the user says "plan9 cluster", "p9c", or "shared storage".
---

# plan9port cluster (p9c)

One storage node serves a 9P file tree. Agents put inputs in `/share`, run
the heavy command on the node, and write the result back to `/share`. Other
agents read it from there.

| Part | Where |
|---|---|
| Storage node | `$P9C_HOST` (SSH login, see "This setup" at the end if present) |
| File server | plan9port fossil on `tcp!127.0.0.1!5640` on the node, backed by venti; data in `~/plan9` there |
| Writable tree | `/share` (world-writable; every agent uses it) |
| Client | `p9c` in `~/.local/bin` on the node: plan9port's `9p` aimed at the server |
| CPU | the storage node; check `uptime` before a heavy job |

The server listens on 127.0.0.1 only and has authentication off. SSH is the
access control: never open port 5640 to a network.

## Use it

On the node:

```sh
p9c ls -l /share
p9c create /share/in.txt              # create an empty file
p9c write /share/in.txt <in.txt
p9c read /share/in.txt >copy.txt
p9c rm /share/in.txt
```

From another machine with SSH to the node (the server is only on the node's
loopback). A non-interactive SSH shell may not have `~/.local/bin` in
`PATH`, so each line adds it:

```sh
ssh "$P9C_HOST" 'PATH=$PATH:~/.local/bin; p9c create /share/in.bin; p9c write /share/in.bin' <in.bin
ssh "$P9C_HOST" 'PATH=$PATH:~/.local/bin; p9c read /share/in.bin | xz -9 -T0 | (p9c create /share/out.xz; p9c write /share/out.xz)'
ssh "$P9C_HOST" 'PATH=$PATH:~/.local/bin; p9c read /share/out.xz' >out.xz
```

The second line is the CPU-offload pattern: the input comes from `/share`,
the work runs on the node, and the result goes back to `/share`.

On Windows, PowerShell has no `<` redirection and adds CRLF to piped text:
run these lines through `cmd /c "..."`.

## Set up a node

1. Install plan9port. Build fossil with `patches/fossil-remove-uaf.diff`
   (stock fossil crashes when a client removes a file).
2. Copy `bin/p9c-server` and `bin/p9c` to `~/.local/bin`.
3. Run `P9C_FOSSIL=/path/to/patched/fossil p9c-server` under a supervisor
   (runit: `service/runit/run`; replace USER, put it in `/etc/sv/p9c-server`,
   link it into the service directory).
   The first start formats `~/plan9` (arena size `P9C_ARENAS`, default 4G).

## Check that it works

On the node, in a clone of github.com/equwal/plan9port-cluster:

```sh
P9C=~/.local/bin/p9c sh tests/roundtrip.sh   # prints PASS
```

## Mount it (Linux, optional)

As root on the node, the kernel 9P client mounts the tree (fossil speaks
plain 9P2000):

```sh
modprobe 9p
mount -t 9p -o trans=tcp,port=5640,version=9p2000,aname=main/active,uname=$USER,access=any 127.0.0.1 /mnt/p9c
```

A server restart breaks the mount: unmount and mount again.

## Gotchas

- `p9c create` fails if the file exists; `p9c write` then overwrites it.
- If `p9c` says "Connection refused", the server is down: restart it.
- fossil archives to venti daily at 04:00 and keeps an hourly snapshot.
