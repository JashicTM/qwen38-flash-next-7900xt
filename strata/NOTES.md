# Strata notes

`lane.json` is the engine config, with `<HOME>` standing in for the real path. Replace it before starting:

```bash
sed -i "s|<HOME>|$HOME|g" strata/lane.json
```

Strata reads the lane config with `--config`, or you can pass the same flags by hand:

```bash
--max-context 262144 --kv int8 --kv-resident 32768 --spec 4
--prefill auto:32768 --conversation-cache-mib 16384 --conversation-cache-slots 8
```

## Port

The lane in this repo binds `127.0.0.1:8080`. Change `host` and `port` in the JSON if something else holds that port.

## Two rules

1. Expert gate and up must be the same quant type. A mixed pack aborts the load.
2. Leave the n-gram table on SSD. It is about 29 GB and Strata streams it by default.

## VRAM reserve

Keep 3 GiB free if a compositor draws on the same card. That is the `--vram-reserve-mib 3072` passed to `setup.sh`. Without it, the desktop and the engine fight over VRAM and one of them loses.
