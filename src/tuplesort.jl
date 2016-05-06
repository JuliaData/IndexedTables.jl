# Hacks and duplications to override tuple methods from base.
# Needs a cleaner solution.

using Base.Order
import Base: searchsortedfirst, searchsortedlast, searchsorted

@generated function isless_tup{N}(t1::NTuple{N}, t2::NTuple{N})
    ex = :()
    for n in N:-1:1
        if n == N
            ex = :(t1[$n] < t2[$n])
        else
            ex = :((t1[$n] == t2[$n]) ? ($ex) : (t1[$n] < t2[$n]))
        end
    end
    ex
end

@generated function isequal_tup{N}(t1::NTuple{N}, t2::NTuple{N})
    ex = :()
    for n in 1:N
        if n == 1
            ex = :(t1[$n] == t2[$n])
        else
            ex = :(($ex) && (t1[$n] == t2[$n]))
        end
    end
    ex
end

cmp_tup(x,y) = isless_tup(x,y) ? -1 : ifelse(isless_tup(y,x), 1, 0)

lt_tup(o::ForwardOrdering,       a, b) = isless_tup(a,b)
lt_tup(o::ReverseOrdering,       a, b) = lt_tup(o.fwd,b,a)


function searchsortedfirst(v::Indexes, x, lo::Int, hi::Int, o::Ordering)
    lo = lo-1
    hi = hi+1
    @inbounds while lo < hi-1
        m = (lo+hi)>>>1
        if lt_tup(o, v[m], x)
            lo = m
        else
            hi = m
        end
    end
    return hi
end

# index of the last value of vector a that is less than or equal to x;
# returns 0 if x is less than all values of v.
function searchsortedlast(v::Indexes, x, lo::Int, hi::Int, o::Ordering)
    lo = lo-1
    hi = hi+1
    @inbounds while lo < hi-1
        m = (lo+hi)>>>1
        if lt_tup(o, x, v[m])
            hi = m
        else
            lo = m
        end
    end
    return lo
end

# returns the range of indices of v equal to x
# if v does not contain x, returns a 0-length range
# indicating the insertion point of x
function searchsorted(v::Indexes, x, ilo::Int, ihi::Int, o::Ordering)
    lo = ilo-1
    hi = ihi+1
    @inbounds while lo < hi-1
        m = (lo+hi)>>>1
        if lt_tup(o, v[m], x)
            lo = m
        elseif lt_tup(o, x, v[m])
            hi = m
        else
            a = searchsortedfirst(v, x, max(lo,ilo), m, o)
            b = searchsortedlast(v, x, m, min(hi,ihi), o)
            return a : b
        end
    end
    return (lo + 1) : (hi - 1)
end
