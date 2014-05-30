fast-copy
=========

Fast Cascade Copy script that use split streams and basic Unix tools to speed up: pigz | tar | netcat | screen | mkfifo

<img src="http://s3.amazonaws.com/easel.ly/all_easels/19186/FastCascadeCopy/image.jpg">

### Restrictions:

#### 0) Remote Secure Shell and sudo 

Script connect to each host using SSH, on which setting up (execute) specific tasks with sudo.
That means you need to settup SSH keys, and configure sudoers on all hosts.

#### 1) Required tools

* nc     - Till now it supports traditional nc (netcat)
* mkfifo - Needed for creating a splitted stream
* pigz   - A parallel implementation of gzip for modern multi-processor, multi-core machines.
* screen - For detaching background jobs

#### 2) Destination directory must be empty or not exist

This restriction exists for two reasons:
1. Safety reason - nothing gonna be overwritten if you made mistake
2. It would be harder to implement check sum verificaton

### Usage

```
usage: -s|--source HOST_0:/path
       -d|--destination HOST_1:/path [HOST_2:/path]...[HOST_N:/path]
       -p|--port 2222            default is 2222
       -v|--verify               verify if sum controls match on all hosts
       -o|--only_verify          only verify without copying

ex.: fcp.sh -v -s dbmaster:/var/lib/mysql/data -d dblag:/var/lib/mysql/data db:/var/lib/mysql/data
```
