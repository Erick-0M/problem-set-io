# Re-run every estimation of pset_io.ipynb with a tighter inner loop (contraction), more optimizer
# iterations and more starting points. Estimates go to models_precise/ (models/ is left untouched).
# Run from code/scripts:  julia --project=julia reestimate_precise.jl
using MAT, DataFrames, Statistics, LinearAlgebra, JLD2, Random
include("blp.jl"); using .blp

const TOLER = 1e-12      # was 1e-3
const MAX_ITER = 10_000  # was 1000
const NS = 20            # was 1 starting point
const ITERATIONS = 200   # optimizer iterations per start (demand was 1000, joint 100)
const TIME_LIMIT = 300.0 # seconds per start; a start that hits it returns its best point so far
const OUTDIR = "models_precise"
mkpath(OUTDIR)

beta = [5, 1, 1]; alpha_bar = -1; gamma = [2, 1, 1]; sigma = 1.0

simdir = "../build/input/public/simulation"
d1 = matread(joinpath(simdir, "10markets3products.mat"))
d2 = matread(joinpath(simdir, "100markets3products.mat"))

function process_data(d)
    J, T = size(d["P_opt"])
    p = reshape(d["P_opt"], (T*J, 1)); shares = reshape(d["shares"], (T*J, 1))
    data = blp.BLPData(T, J, d["x1"], p, shares, log.(d["alphas"] .- 1))
    model = blp.BLPDemand(BLPData = data)
    model.xi_real = d["xi_all"]
    model.cost = gamma[1] .+ (gamma[2] * d["w"] + gamma[3] * d["Z"] + d["eta"])
    model.markup .= ((model.p - model.cost) ./ model.p)
    model.profit = (model.p - model.cost) .* model.shares
    return model
end

function estimate!(model, name)
    println("Estimating $name ..."); flush(stdout)
    failures = []   # starts that errored: (sigma0, error); the search continues with the other starts
    kw = (toler = TOLER, max_iter = MAX_ITER, Ns = NS, iterations = ITERATIONS, time_limit = TIME_LIMIT, failures = failures)
    t = @elapsed if model isa blp.BLPDemand
        blp.estimate_blp!(model; kw...)
    else
        blp.estimate_blp_joint!(model; kw...)
    end
    jldsave(joinpath(OUTDIR, "$name.jdl2"); model = model)
    jldsave(joinpath(OUTDIR, "$(name)_failed_starts.jdl2"); failures = failures)
    println("  $(length(failures)) of $NS starts failed")
    println("  done in $(round(t, digits = 1))s; params = ", round.(vec(model isa blp.BLPDemand ? model.params : model.params), digits = 4))
    return model
end

# ---- T=100, J=3 baseline (true parameters assigned as in the notebook) ----
model = process_data(d2)
model.beta .= vcat(beta, [alpha_bar]); model.sigma = sigma
delta = model.X_all * model.beta + model.xi_real
blp.simulate_BLP!(model, delta = delta, sigma = sigma, all = true)

price_bar = blp.compute_hausman(model)
X_rivals = blp.compute_blp(model)
model.Z = hcat(model.X, price_bar, X_rivals); model.W = inv(model.Z' * model.Z)
model = estimate!(model, "model")

# ---- T=10, J=3 ----
model_ls = process_data(d1)
p_bar_ls = blp.compute_hausman(model_ls); X_rivals_ls = blp.compute_blp(model_ls)
model_ls.Z = hcat(model_ls.X, p_bar_ls, X_rivals_ls); model_ls.W = inv(model_ls.Z' * model_ls.Z)
model_ls = estimate!(model_ls, "model_ls")

# ---- price as its own instrument ----
model_inc = deepcopy(model)
model_inc.Z = hcat(model_inc.X_all, price_bar, X_rivals); model_inc.W = inv(model_inc.Z' * model_inc.Z)
model_inc = estimate!(model_inc, "model_inc")

# ---- + cost shifter w as demand instrument ----
model_ss = deepcopy(model)
model_ss.Z = hcat(model_ss.X, price_bar, X_rivals, d2["w"]); model_ss.W = inv(model_ss.Z' * model_ss.Z)
model_ss = estimate!(model_ss, "model_ss")

model_ls_ss = deepcopy(model_ls)
model_ls_ss.Z = hcat(model_ls_ss.X, p_bar_ls, X_rivals_ls, d1["w"]); model_ls_ss.W = inv(model_ls_ss.Z' * model_ls_ss.Z)
model_ls_ss = estimate!(model_ls_ss, "model_ls_ss")   # notebook saved this one over "model_ss"; kept separate here

# ---- joint demand + supply under three conduct assumptions ----
X_supply = hcat(ones(model.T * model.J, 1), d2["Z"], d2["w"])
Z_supply = hcat(model.X, X_rivals, X_supply[:, 2:end])
model_supply = blp.BLPSupply(X = X_supply, Z = Z_supply, W = inv(Z_supply' * Z_supply))

for (name, Omega) in (("bert", nothing), ("coll", ones(model.J, model.J)), ("comp", zeros(model.J, model.J)))
    dem = deepcopy(model_ss)
    Omega === nothing || (dem.Omega = Omega)
    sys = blp.BLP(BLPDemand = dem, BLPSupply = deepcopy(model_supply))
    estimate!(sys, "model_system_$name")
end
println("All estimates saved in $OUTDIR/")
