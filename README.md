# A toy Free-CHR implementation
CHR: Constraint Handling Rules

# Features
* no allocations
* no dependencies
* simple syntax with state management helpers.  simple runner.
* guard() and body() methods both pass state by reference to allow in place mutation and to avoid potential large copies

# Use
```sh
$ zig build fetch --save git+https://github.com/travisstaloch/freechr
```

# Examples
see tests at bottom of [src/root.zig](src/root.zig)

# Resources
* https://en.wikipedia.org/wiki/Constraint_Handling_Rules
* https://gist.github.com/SRechenberger/d5e1eb875ae72ce5cafe6ea1c5b3ee38#file-freechr-py
* https://arxiv.org/pdf/2306.00642v4
