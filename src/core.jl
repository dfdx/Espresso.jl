
# core.jl - single place to load all package definitions.
#
# If you are willing to learn the package structure, just go through
# included files one by one, read header notes and other comments

using DataStructures
using Einsum
using Sugar

include("utils.jl")
include("types.jl")
include("rewrite.jl")
include("simplify.jl")
include("funexpr.jl")
include("indexing.jl")
include("exnode.jl")
include("exgraph.jl")
include("expand_temp.jl")
include("expand_deps.jl")
include("optimize.jl")
include("propagate_size.jl")
include("merge.jl")
include("to_einstein.jl")
include("from_einstein.jl")

