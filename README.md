fast-copy
=========

Fast Cascade Copy script that use split streams and basic Unix tools to speed up: pigz | tar | netcat | screen | mkfifo

<img src="https://s3.amazonaws.com/easel.ly/all_easels/19186/FastCascadeCopy/image.jpg">

### Usage

```
usage: -s|--source HOST:/path
       -d|--destination HOST_A:/pash [HOST_B:/path]...[HOST_N:/path]
       -p|--port 2222 (default 2222)
ex.: fcp.sh -s dbmaster:/var/lib/mysql/data -d dblag:/var/lib/mysql/data db:/var/lib/mysql/data
```
