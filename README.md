fast-copy
=========

Fast Cascade Copy script that use split streams and basic Unix tools to speed up: pigz | tar | netcat | screen | mkfifo

<img src="https://s3.amazonaws.com/easel.ly/all_easels/19186/FastCascadeCopy/image.jpg">

### Usage

```
usage: -s|--source HOST_0:/path
       -d|--destination HOST_1:/path [HOST_2:/path]...[HOST_N:/path]
       -p|--port 2222            default is 2222
       -v|--verify               verify if sum controls match on all hosts
       -o|--only_verify          only verify without copying

ex.: fcp.sh -v -s dbmaster:/var/lib/mysql/data -d dblag:/var/lib/mysql/data db:/var/lib/mysql/data
```
