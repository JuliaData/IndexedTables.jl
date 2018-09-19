using Test, IndexedTables, OnlineStats, DataValues, WeakRefStrings
import DataValues: NA

@testset "IndexedTables" begin

include("test_core.jl")
include("test_utils.jl")
include("test_tabletraits.jl")
include("test_collect.jl")

end
