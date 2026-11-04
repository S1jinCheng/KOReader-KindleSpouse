500-book shelf observations

Command: test_home.py --scale in the pinned AppImage, SDL dummy, WSL2 on /mnt/d, 20 logical CPUs. Before the run uptime reported load averages 0.34/0.43/0.20; the independent idle scheduler test also ran. Five rounds cover shelves, sorts, search and clear. Every result is compared with the expected item order and counts; none failed.

This run recorded 58 refreshes: median 3.0 ms, range 2–9 ms. This times cached filtering/sorting and widget updates, not the physical e-ink paint or cold metadata extraction; it is an observation, not a comparative speedup or Scribe latency claim.

The former blocking path was observed in /proc at do_readlinkat through p9_client_rpc. A three-file upstream call-chain probe performs three realpath calls with collection marks enabled and zero with them disabled. The new hot path records zero path resolutions, zero directory scans, zero UI document opens and zero FileManager reinitializations. A real book open/close returns with zero book-directory scans and zero document opens. Upstream sidecar custom-cover lookup on save remains unchanged.
