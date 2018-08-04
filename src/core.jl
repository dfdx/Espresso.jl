 
# core.jl - single place to load all package definitions.
#
# If you want to learn the package structure, just go through
# included files one by one, read header notes and other comments

# using Sugar
using LinearAlgebra
using Statistics
import Base: CodeInfo, Slot

include("types.jl")
include("utils.jl")
include("rewrite.jl")
include("simplify.jl")
include("sugar.jl")
include("funexpr.jl")
include("indexing.jl")
include("preprocess.jl")
include("exnode.jl")
include("exgraph.jl")
include("tracked.jl")
include("evaluate.jl")
include("graph_utils.jl")
include("expand_deps.jl")
include("optimize.jl")
include("merge.jl")
include("inplace.jl")
include("codegen.jl")
include("destruct.jl")
include("helpers.jl")
