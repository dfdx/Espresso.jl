
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
include("exgraph.jl")
include("exgraph_utils.jl")
include("einstein_base.jl")
include("from_einstein.jl")
include("to_einstein.jl")
