| JuliaDB docs | Build | Coverage |
|--------------|-------|----------|
| [![](https://img.shields.io/badge/docs-stable-blue.svg)](http://juliadb.org/stable/) [![](https://img.shields.io/badge/docs-latest-blue.svg)](http://juliadb.org/latest/) | [![Build Status](https://travis-ci.org/JuliaComputing/IndexedTables.jl.svg?branch=master)](https://travis-ci.org/JuliaComputing/IndexedTables.jl)| [![codecov.io](https://codecov.io/github/JuliaComputing/IndexedTables.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaComputing/IndexedTables.jl?branch=master) |

# IndexedTables.jl

**IndexedTables** provides tabular data structures where some of the columns form a sorted index.
It provides the backend to [JuliaDB](https://github.com/JuliaComputing/JuliaDB.jl), but can
be used on its own for efficient in-memory data processing and analytics.

## Data Structures 

IndexedTables offers two data structures: `IndexedTable` and `NDSparse`.

- **Both types store data _in columns_**.
- **`IndexedTable` and `NDSparse` differ mainly in how data is accessed.**
- **Both types have equal performance for Table operations (`select`, `filter`, etc.).** 


## Quickstart

```
using Pkg
Pkg.add("IndexedTables")
using IndexedTables

t = table((x = 1:100, y = randn(100)))

select(t, :x)

filter(row -> row.y > 0, t)
```

## `IndexedTable` vs. `NDSparse`

First let's create some data to work with.

```julia
using Dates

city = vcat(fill("New York", 3), fill("Boston", 3))

dates = repeat(Date(2016,7,6):Day(1):Date(2016,7,8), 2)

vals = [91, 89, 91, 95, 83, 76]
```

### IndexedTable

- (Optionally) Sorted by primary key(s), `pkey`.
- Data is accessed as a Vector of NamedTuples.

```julia
using IndexedTables

julia> t1 = table((city = city, dates = dates, values = vals); pkey = [:city, :dates])
Table with 6 rows, 3 columns:
city        dates       values
──────────────────────────────
"Boston"    2016-07-06  95
"Boston"    2016-07-07  83
"Boston"    2016-07-08  76
"New York"  2016-07-06  91
"New York"  2016-07-07  89
"New York"  2016-07-08  91

julia> t1[1]
(city = "Boston", dates = 2016-07-06, values = 95)
```

### NDSparse

- Sorted by index variables (first argument).
- Data is accessed as an N-dimensional sparse array with arbitrary indexes.

```julia
julia> t2 = ndsparse((city=city, dates=dates), (value=vals,))
2-d NDSparse with 6 values (1 field named tuples):
city        dates      │ value
───────────────────────┼──────
"Boston"    2016-07-06 │ 95
"Boston"    2016-07-07 │ 83
"Boston"    2016-07-08 │ 76
"New York"  2016-07-06 │ 91
"New York"  2016-07-07 │ 89
"New York"  2016-07-08 │ 91

julia> t2["Boston", Date(2016, 7, 6)]
(value = 95)
```

## Get started

For more information, check out the [JuliaDB Documentation](http://juliadb.org/latest/index.html).
