[![Build Status](https://travis-ci.org/JuliaComputing/IndexedTables.jl.svg?branch=master)](https://travis-ci.org/JuliaComputing/IndexedTables.jl)

[![codecov.io](http://codecov.io/github/JuliaComputing/IndexedTables.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaComputing/IndexedTables.jl?branch=master)

# IndexedTables.jl
This package provides a tablular data structure where some of the columns form a sorted index.
This structure is equivalent to an N-dimensional sparse array, and follows the array API
to the extent possible.

## Introduction

The data structure (`IndexedTable`) provided by this package maps tuples of indices
to data values.
Hence, it is similar to a hash table mapping tuples to values, but with a few key
differences.
First, the index tuples are stored columnwise, with one vector per index position:
there is a vector of first indices, a vector of second indices, and so on.
The index vectors are expected to be homogeneous to allow more efficient storage.
Second, the indices must have a total order, and are stored lexicographically sorted
(first by the first index, then by the second index, and so on, left-to-right).
While the indices must have totally-ordered types, the data values can be anything.
Finally, for purposes of many operations an `IndexedTable` acts like an N-dimensional
array of its data values, where the number of dimensions is the number of index
columns.

## Construction

The `IndexedTable` constructor accepts a series of vectors.
The last vector contains the data values, and the first N vectors contain the
indices for each of the N dimensions.
The name `Table` is provided as an optional shorthand for `IndexedTable`, not
exported by default to avoid name conflicts.
As an example, let's construct an array of the high temperatures for three days
in two cities:

    julia> using Base.Dates
    julia> using IndexedTables.Table
    julia> hitemps = Table([fill("New York",3); fill("Boston",3)],
                           repmat(Date(2016,7,6):Date(2016,7,8), 2),
                           [91,89,91,95,83,76])
    ───────────────────────┬───
    "Boston"    2016-07-06 │ 95
    "Boston"    2016-07-07 │ 83
    "Boston"    2016-07-08 │ 76
    "New York"  2016-07-06 │ 91
    "New York"  2016-07-07 │ 89
    "New York"  2016-07-08 │ 91

Notice that the data was sorted first by city name, then date, giving a different
order than we initially provided.
On construction, `Table` takes ownership of the columns and sorts them in place
(the original vectors are modified).

## Permuting dimensions

As with other multi-dimensional arrays, dimensions can be permuted to change
the sort order.
With `Table` the interpretation of this operation is especially natural:
simply imagine passing the index columns to the constructor in a different order,
and repeating the sorting process:

    julia> permutedims(hitemps, [2, 1])
    ───────────────────────┬───
    2016-07-06  "Boston"   │ 95
    2016-07-06  "New York" │ 91
    2016-07-07  "Boston"   │ 83
    2016-07-07  "New York" │ 89
    2016-07-08  "Boston"   │ 76
    2016-07-08  "New York" │ 91

Now the data is sorted first by date.
In some cases such dimension permutations are needed for performance.
The leftmost column is esssentially the primary key --- indexing is fastest
in this dimension.

## Importing data

Importing data from column-based sources is straightforward.
For example, csv files can be imported this way:

    julia> using IndexedTables, IndexedTables.Table
    julia> using CSV
    julia> table = Table(CSV.read(filename).columns...)

Of course, this assumes the file already has the "data column" in the rightmost
position.
If not, first reorder the columns.

## Indexing

Most lookup and filtering operations on an `IndexedTable` are done via indexing.
Our `hitemps` array behaves like a 2-d array of integers, accepting two
indices:

    julia> hitemps["Boston", Date(2016,7,8)]
    76

If the given indices exactly match the element types of the index columns,
then the result is a scalar.
In other cases, a new `IndexedTable` is returned, giving data for all matching
locations:

    julia> hitemps["Boston", :]
    ─────────────────────┬───
    "Boston"  2016-07-06 │ 95
    "Boston"  2016-07-07 │ 83
    "Boston"  2016-07-08 │ 76

As with other array types, `IndexedTable` generates its data values when iterated.
This allows the usual reduction functions in Base (and some others) to work:

    julia> maximum(hitemps["Boston", :])
    95

## Select and aggregate

In some cases one wants to consider a subset of dimensions, for example
when producing a simplified summary of data.
This can be done by passing dimension (column) numbers to `select`:

    julia> select(hitemps, 2)
    ───────────┬───
    2016-07-06 │ 95
    2016-07-06 │ 91
    2016-07-07 │ 83
    2016-07-07 │ 89
    2016-07-08 │ 76
    2016-07-08 │ 91

In this case, the result has multiple values for some indices, and so
does not fully behave like a normal array anymore.
Operations that might leave the array in such a state accept the keyword
argument `agg`, a function to use to combine all values associated
with the same indices:

    julia> select(hitemps, 2, agg=max)
    ───────────┬───
    2016-07-06 │ 95
    2016-07-07 │ 89
    2016-07-08 │ 91

The `Table` constructor also accepts the `agg` argument.
The aggregation operation can also be done by itself, in-place, using the
function `aggregate!`.

Calling `select` with `column=>predicate` will apply that predicate to the column:

    julia> select(hitemps, 2=>isfriday)
    ───────────────────────┬───
    "Boston"    2016-07-08 │ 76
    "New York"  2016-07-08 │ 91

## Iterators

Indexing makes a copy of the selected data, and therefore can be expensive.
As an alternative, it is possible to construct an iterator over a subset of
an `Table`.
The `where` function accepts the same arguments as indexing, but instead
returns an iterator that generates the data values at the selected
locations:

    julia> bos = where(hitemps, "Boston", :);
    julia> first(bos)
    95

The `pairs` function is similar, except yields `index=>value` pairs (where
`index` is a tuple).

## Broadcasting

`broadcast` is used to combine data with slightly different dimensions.
For example, say we have an array of low temperatures for Boston broken
down by zip code:

    julia> lotemps = Table(fill("Boston",6),
                           repeat(Date(2016,7,6):Date(2016,7,8), inner=2),
                           repmat([02108,02134], 3),
                           [71,70,67,66,65,66])
    ───────────────────────────┬───
    "Boston"  2016-07-06  2108 │ 71
    "Boston"  2016-07-06  2134 │ 70
    "Boston"  2016-07-07  2108 │ 67
    "Boston"  2016-07-07  2134 │ 66
    "Boston"  2016-07-08  2108 │ 65
    "Boston"  2016-07-08  2134 │ 66

We want to compute the daily temperature range (high minus low).
Since we don't have high temperatures available per zip code, we will assume
the high temperatures are city-wide averages applicable to every zip code.
The `broadcast` function implements this interpretation of the data,
automatically repeating data along missing dimensions:

    julia> broadcast(-, hitemps, lotemps)
    ───────────────────────────┬───
    "Boston"  2016-07-06  2108 │ 24
    "Boston"  2016-07-06  2134 │ 25
    "Boston"  2016-07-07  2108 │ 16
    "Boston"  2016-07-07  2134 │ 17
    "Boston"  2016-07-08  2108 │ 11
    "Boston"  2016-07-08  2134 │ 10

Notice that `broadcast` also automatically performs an inner join, selecting
only rows that match.

`broadcast` currently matches dimensions based on element type.
Specifying dimensions to match manually, or based on column names, is planned
future functionality.

## Converting dimensions

A location in the coordinate space of an array often has multiple possible
descriptions.
This is especially common when describing data at different levels of detail.
For example, a point in time can be expressed at the level of seconds, minutes,
or hours.
In our toy temperature dataset, we might want to look at monthly instead of
daily highs.

This can be accomplished using the `convertdim` function.
It accepts an array, a dimension number to convert, a function or dictionary
to apply to indices in that dimension, and an aggregation function (the
aggregation function is needed in case the mapping is many-to-one).
The following call therefore gives monthly high temperatures:

    julia> convertdim(hitemps, 2, month, agg=max)
    ──────────────┬───
    "Boston"    7 │ 95
    "New York"  7 │ 91

## Assignment

`IndexedTable` supports indexed assignment just like other arrays, but there are
caveats.
Since data is stored in a compact, sorted representation, inserting a single
element is potentially very inefficient (`O(n)`, since it requires moving up to half
of the existing elements).
Therefore single-element insertions are accumulated into a temporary buffer to
amortize cost.

When the next whole-array operation (e.g. indexing or broadcast) is performed,
the temporary buffer is merged into the main storage.
This operation is called `flush!`, and can also be invoked explicitly.
The cost of this operation is `O(n*log(n)) + O(m)`, where `n` is the number
of inserted items and `m` is the number of existing items.
This means that the worst case occurs when alternating between inserting a
small number of items, and performing whole-array operations.
To the extent possible, insertions should be batched, and in general done
rarely.

## Named columns

An `IndexedTable` is built on a simpler data structure called `Columns` that groups
a set of vectors together.
This structure is used to store the index part of an `IndexedTable`, and an
`IndexedTable` can be constructed by passing one of these objects directly.
`Columns` allows names to be associated with its constituent vectors.
Together, these features allow `Table` arrays with named dimensions:

    julia> hitemps = Table(Columns(city = [fill("New York",3); fill("Boston",3)],
                                   date = repmat(Date(2016,7,6):Date(2016,7,8), 2)),
                           [91,89,91,95,83,76])
    city        date       │ 
    ───────────────────────┼───
    "Boston"    2016-07-06 │ 95
    "Boston"    2016-07-07 │ 83
    "Boston"    2016-07-08 │ 76
    "New York"  2016-07-06 │ 91
    "New York"  2016-07-07 │ 89
    "New York"  2016-07-08 │ 91

Now dimensions (e.g. in `select` operations) can be identified by symbol
(e.g. `:city`) as well as integer index.

A `Columns` object itself behaves like a vector, and so can be used
to represent the data part of an `Table`.
This provides one possible way to store multiple columns of data:

    julia> Table(Columns(x = rand(4), y = rand(4)),
                 Columns(observation = rand(1:2,4), confidence = rand(4)))
    x          y        │ observation  confidence
    ────────────────────┼────────────────────────
    0.0400914  0.385859 │ 1            0.983784
    0.165966   0.915532 │ 1            0.206534
    0.532029   0.631039 │ 2            0.196016
    0.932271   0.350075 │ 1            0.716692

In this case the data elements are structs with fields `observation`
and `confidence`, and can be used as follows:

    julia> filter(d->d.confidence > 0.90, ans)
    x          y        │ observation  confidence
    ────────────────────┼────────────────────────
    0.0400914  0.385859 │ 1            0.983784
