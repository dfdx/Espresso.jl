
using Documenter, Espresso

makedocs()

deploydocs(
    deps   = Deps.pip("mkdocs", "python-markdown-math"),
    repo = "github.com/dfdx/Espresso.jl.git",
    julia  = "0.6"
)
