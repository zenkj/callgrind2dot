callgrind2dot
=============

callgrind file to dot file transformation

usage
=====

```
callgrind2dot> lua callgrind2dot.lua
a callgrind file should be specified
Usage:
    lua callgrind2dot.lua [options] callgrind-file
Options:
    --list-functions            list all functions mentioned, in this;
                                case the --threshold is ignored;
    --threshold=<threshold>     the threshold of Instruction percentage
                                that function under <threshold>% will not
                                be generated in the dot file. the range
                                is 0.0 ~ 100.0, default is 1.0;
    --focus-funtion=<function>  generate dot file for function
                                <function> and its caller and callee;
    --dot-file=<dotfile>        write the output to dot file <dotfile>
                                default is to write the output to standard
                                output.
```

example
=======

* list functions
```
lua callgrind2dot.lua --list-functions test/test.callgrind
                function    cost    count       object-file      source-file
           luaD_growstack     0.04          1 /home/jzjian/bin/lua           ???                           
      _IO_flush_all_lockp     0.00          1 /lib/x86_64-linux-gnu/libc-2.15.so /build/buildd/eglibc-2.15/libio/genops.c
   _dl_check_all_versions     0.44          1 /lib/x86_64-linux-gnu/ld-2.15.so /build/buildd/eglibc-2.15/elf/dl-version.c
          luaL_checkudata     0.17          9 /home/jzjian/bin/lua           ???                           
                    isinf     0.00          1 /lib/x86_64-linux-gnu/libc-2.15.so /build/buildd/eglibc-2.15/math/../sysdeps/ieee754/dbl-64/wordsize-64/s_isinf.c
                   f_call    78.46          1 /home/jzjian/bin/lua           ???                           
                  pushstr     0.03          3 /home/jzjian/bin/lua           ???                           
```

* focus on function
```
lua callgrind2dot.lua --focus-function=pmain --dot-file=test/pmain.dot test/test.callgrind
dot -Tpng -otest/pmain.png test/pmain.dot
```
![pmain](https://raw.github.com/zenkj/callgrind2dot/master/test/pmain.png)

history
=======

There's a great tool called gprof2dot written in python(http://gprof2dot.jrfonseca.googlecode.com/) already.
This tool is claimed to be able to handle callgrind file format. After some trial, I find the output dot file
has wrong cost percentage. I reported this issue to the auther. During the time to wait for the author to fix
this issue, I plan to write one by myself.

After some research on the callgrind file format, I find it's a very simple format. So it should be enough
to write this tool in my favorite script language lua. At last this project is created.

BTW, the author of gprof2dot has already fixed that issue(still not try it because of this project).
