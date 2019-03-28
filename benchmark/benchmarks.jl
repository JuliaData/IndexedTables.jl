using PkgBenchmark
using IndexedTables
using IntervalSets: (..)

Random.seed!(666)

@benchgroup "construction" begin
    N = 10000
    a = rand(0:0.001:2, N)
    b = rand(0:0.001:2, N)
    c = rand(N)

    sorted = sort!(Columns(a, b))

    @bench "vectors" IndexedTable(a, b, c)
    @bench "vectors-agg" IndexedTable(a, b, c, agg=+)
    #@bench "sorted" IndexedTable(sorted, agg=+, presorted=true)
    @bench "vectors-in-place" IndexedTable(a, b, c, copy=false)
end

@benchgroup "indexing" begin
    N = 10000
    a = rand(0:0.001:2, N)
    b = rand(0:0.001:2, N)
    c = rand(N)

    t1 = IndexedTable(a, b, c, agg=+)
    i, j = t1.index[rand(1:length(t1))]

    # fast cases:
    @bench "const-const" $t1[$i, $j]
    @bench "colon-const" $t1[:, $j]
    @bench "colon-colon" $t1[:, :]

    @bench "interval-colon" $t1[0.2..0.8, :]
    @bench "interval-const" $t1[0.2..0.8, $j]
    @bench "const-interval" $t1[$i, 0.2..0.8]

    # slow cases
    @bench "range-colon" $t1[0.2:eps():0.8, :]
    @bench "range-const" $t1[0.2:eps():0.8, $j]
    @bench "interval-interval" $t1[0.2..0.8, 0.2..0.8]
    @bench "range-interval" $t1[0.2:eps():0.8, 0.2..0.8]

    x = sort!(a[200:800])
    @bench "vector-interval" $t1[$x, 0.2..0.8]
    y = sort!(b[400:600])
    @bench "vector-vector" $t1[$x, $y]
end

let
    N = 10000
    a = rand(0:0.001:2, N)
    b = rand(0:0.001:2, N)
    c = rand(N)
    t1 = IndexedTable(a, b, c, agg=+)
    @benchgroup "select" begin
        @bench "select-filter" select($t1, 1 => x -> x > 0.5, 2 => x -> x < 0.5)
        @bench "select-pick-1" select($t1, 1, agg=+)
        @bench "select-pick-2" select($t1, 2, agg=+)
    end

    t2 = IndexedTable(a, b, Columns(c, rand(N)))
    t3 = IndexedTable(a, b, Columns(c, [randstring(2) for i=1:N]))
    @benchgroup "filter" begin
        @bench "filter-float" filter(x->x>0.5, $t1)
        @bench "filter-float-float" filter(x->x[1]>0.5, $t2)
        # the below is much slower than the above
        # since each x is stack allocated
        @bench "filter-float-string" filter(x->x[1]>0.5, $t3)
    end

    @benchgroup "aggregate" begin
        N = 10000
        a = rand(1:10, N)
        b = rand(1:10, N)
        c = rand(N)
        t4 = IndexedTable(a, b, c)
        @bench "in-place" aggregate!(+, $(copy(t4)))
        @bench "out-of-place" aggregate(+, $(copy(t4)))
        @bench "vec" aggregate_vec(sum, $t4)
    end

    @benchgroup "reducedim" begin
        N = 10000
        a = rand(0:0.001:2, N)
        b = rand(0:0.001:2, N)
        c = rand(N)
        t4 = IndexedTable(a, b, c)
        @bench "dim-1" reduce(+, $t4, dims=1)
        @bench "dim-2" reduce(+, $t4, dims=2)
        @bench "vec-dim-1" reducedim_vec(+, $t4, 1)
        @bench "vec-dim-2" reducedim_vec(+, $t4, 2)
    end

    let

        function maketable(N)
            a = rand(0:0.001:2, N)
            b = rand(0:0.001:2, N)
            c = rand(N)
            IndexedTable(a, b, c)
        end
        big1 = maketable(10000)
        big2 = maketable(10000)
        small1 = maketable(1000)
        small2 = maketable(1000)
        @benchgroup "innerjoin" begin
            @bench "small-small" innerjoin($small1, $small2)
            @bench "small-big"   innerjoin($small1, $big1)
            @bench "big-small"   innerjoin($big1, $small1)
            @bench "big-big"     innerjoin($big1, $big2)
        end

        @benchgroup "leftjoin" begin
            @bench "small-small" leftjoin($small1, $small2)
            @bench "small-big"   leftjoin($small1, $big1)
            @bench "big-small"   leftjoin($big1, $small1)
            @bench "big-big"     leftjoin($big1, $big2)

            @bench "in-place-small-small" leftjoin!($(copy(small1)), $small2)
            @bench "in-place-small-big"   leftjoin!($(copy(small1)), $big1)
            @bench "in-place-big-small"   leftjoin!($(copy(big1)), $small1)
            @bench "in-place-big-big"     leftjoin!($(copy(big1)), $big2)
        end
    end

    @benchgroup "merge" begin
        @bench "small-small" merge($small1, $small2)
        @bench "small-big"   merge($small1, $big1)
        @bench "big-small"   merge($big1, $small1)
        @bench "big-big"     merge($big1, $big2)

        @bench "small-small-agg" merge($(copy(small1)),$(copy(small2)), agg=+)
        @bench "small-big-agg"   merge($(copy(small1)),$(copy(big1)), agg=+)
        @bench "big-small-agg"   merge($(copy(big1)),  $(copy(small1)), agg=+)
        @bench "big-big-agg"     merge($(copy(big1)),  $(copy(big2)), agg=+)
    end

    @benchgroup "asofjoin" begin
        @bench "small-small" asofjoin($small1, $small2)
        @bench "small-big"   asofjoin($small1, $big1)
        @bench "big-small"   asofjoin($big1, $small1)
        @bench "big-big"     asofjoin($big1, $big2)
    end
end

