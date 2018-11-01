| JuliaDB docs | Build | Coverage |
|--------------|-------|----------|
| [![](https://img.shields.io/badge/docs-stable-blue.svg)](http://juliadb.org/stable/) [![](https://img.shields.io/badge/docs-latest-blue.svg)](http://juliadb.org/latest/) | [![Build Status](https://travis-ci.org/JuliaComputing/IndexedTables.jl.svg?branch=master)](https://travis-ci.org/JuliaComputing/IndexedTables.jl)| [![codecov.io](https://codecov.io/github/JuliaComputing/IndexedTables.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaComputing/IndexedTables.jl?branch=master) |

# IndexedTables.jl

**IndexedTables** provides tabular data structures where some of the columns form a sorted index.
It provides the backend to [JuliaDB](https://github.com/JuliaComputing/JuliaDB.jl), but can
be used on its own for efficient in-memory data processing and analytics.

## Data Structures 

- **The two table types in IndexedTables differ in how data is accessed.**
- **There is no performance difference between table types for operations such as selecting, filtering, and map/reduce.**

First let's create some data to work with.

```julia
using Dates

city = vcat(fill("New York", 3), fill("Boston", 3))

dates = repeat(Date(2016,7,6):Day(1):Date(2016,7,8), 2)

values = [91, 89, 91, 95, 83, 76]
```

### Table

- Data is accessed as a Vector of NamedTuples.  
- Sorted by primary key(s), `pkey`.

```julia
using IndexedTables

julia> t1 = table((city = city, dates = dates, values = values); pkey = [:city, :dates])
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

julia> first(t1)
(city = "Boston", dates = 2016-07-06, values = 95)
```

### NDSparse

- Data is accessed as an N-dimensional sparse array with arbitrary indexes.
- Sorted by index variables (first argument).

```julia
julia> t2 = ndsparse(@NT(city=city, dates=dates), @NT(value=values))
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

julia> first(t2)
(value = 95)
```

As with other multi-dimensional arrays, dimensions can be permuted to change the sort order:

```julia
julia> permutedims(t2, [2,1])
2-d NDSparse with 6 values (1 field named tuples):
dates       city       │ value
───────────────────────┼──────
2016-07-06  "Boston"   │ 95
2016-07-06  "New York" │ 91
2016-07-07  "Boston"   │ 83
2016-07-07  "New York" │ 89
2016-07-08  "Boston"   │ 76
2016-07-08  "New York" │ 91
```

## Get started

For more information, check out the [JuliaDB API Reference](http://juliadb.org/latest/api/datastructures.html).
