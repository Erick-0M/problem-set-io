module blp

    using MAT, DataFrames, Statistics, Plots, LinearAlgebra, Optim, NLSolversBase, Random, LinearAlgebra, BlockDiagonals
    

    struct BLPData
        T::Int
        J::Int  
        
        X::Matrix{Float64} 
        p::Matrix{Float64} 
        shares::Matrix{Float64} 
        errors::Matrix{Float64}

    end

    Base.@kwdef mutable struct BLPDemand
        

        BLPData::BLPData

        T::Int = BLPData.T
        J::Int  = BLPData.J 

        X::Matrix{Float64} = BLPData.X
        p::Matrix{Float64} = BLPData.p
        shares::Matrix{Float64} = BLPData.shares
        errors::Matrix{Float64} = BLPData.errors

        shares_0::Matrix{Float64}   = reshape(repeat(1.0 .- sum(reshape(shares, J, T), dims=1), inner=(J, 1)), (T*J, 1))

        Z::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        W::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        M::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        moments::Matrix{Float64}    = Matrix{Float64}(undef, 0, 0)
        k_Z::Union{Missing, Int}    = missing

        R::Int                      = size(errors)[2]
        k::Int                      = size(X)[2] + 1
        X_all::Matrix{Float64}      = hcat(X, p)
        sigma::Union{Missing, Float64}    = missing # This would usually will be a matrix          
        beta::Matrix{Float64}       = Matrix{Float64}(undef, k, 1)
        alphas::Matrix{Float64}     = Matrix{Float64}(undef, T * J, R)
        xi::Matrix{Float64}         = Matrix{Float64}(undef, T * J, 1)
        xi_real::Matrix{Float64}    = Matrix{Float64}(undef, T * J, 1)
        delta::Matrix{Float64}      = Matrix{Float64}(undef, T * J, 1)
        v::Matrix{Float64}          = Matrix{Float64}(undef, T, R)
        shares_sim::Matrix{Float64} = Matrix{Float64}(undef, T * J, 1)
        
        Var::Matrix{Float64}        = Matrix{Float64}(undef, k + 1, k + 1)
        util::Matrix{Float64}       = Matrix{Float64}(undef, T * J, R)
        choice::Matrix{Float64}     = Matrix{Float64}(undef, T * J, R)
        ds_dp::Matrix{Float64}      = Matrix{Float64}(undef, T * J, J)
        elas::Matrix{Float64}       = Matrix{Float64}(undef, T * J, J)
        elas_sim::Matrix{Float64}   = Matrix{Float64}(undef, T * J, J)
        markup::Matrix{Float64}     = Matrix{Float64}(undef, T * J, 1)
        markup_sim::Matrix{Float64} = Matrix{Float64}(undef, T * J, 1)
        cost::Matrix{Float64}       = Matrix{Float64}(undef, T * J, 1)
        cost_sim::Matrix{Float64}   = Matrix{Float64}(undef, T * J, 1)
        profit::Matrix{Float64}     = Matrix{Float64}(undef, T * J, 1)
        profit_sim::Matrix{Float64} = Matrix{Float64}(undef, T * J, 1)
        cs::Matrix{Float64}         = Matrix{Float64}(undef, T , 1)
        cs_sim::Matrix{Float64}     = Matrix{Float64}(undef, T , 1)
        ps_sim::Matrix{Float64}     = Matrix{Float64}(undef, T , 1)
        ts_sim::Matrix{Float64}     = Matrix{Float64}(undef, T , 1)
        grad::Matrix{Float64}       = Matrix{Float64}(undef, T * J , 1)
        Omega::Matrix{Float64}      = I(J) # Assumed perform Bertrand
        opt_res::Union{Vector{Any}, Missing} = missing # Optimized results
        params::Matrix{Float64}      = Matrix{Float64}(undef, 0, 0)
    end


    Base.@kwdef mutable struct BLPSupply
        X::Matrix{Float64}          # Linear cost shifters
        k::Int                      = size(X)[2]
        Z::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        W::Matrix{Float64}          = Matrix{Float64}(undef, 0, 0)
        M::Matrix{Float64}          = (I -  X * inv(X' * Z * W * Z' * X) * X'* Z * W * Z');
        moments::Matrix{Float64}    = Matrix{Float64}(undef, 0, 0)
        k_Z::Union{Missing, Int}    = size(Z)[2]
        beta::Matrix{Float64}       = Matrix{Float64}(undef, k, 1)
    end


    Base.@kwdef mutable struct BLP
        BLPDemand::BLPDemand
        BLPSupply::BLPSupply
        k = BLPDemand.k + BLPSupply.k + 1 # Supply and demand parameters and sigma
        opt_res::Union{Vector{Any}, Missing} = missing
        params::Matrix{Float64}   = Matrix{Float64}(undef, 0, 0)
        Var::Matrix{Float64}          = Matrix{Float64}(undef, BLPDemand.T * BLPDemand.J , 1)
    end

    # Simulating the model given delta and sigma
    function simulate_BLP!(model::BLPDemand; delta = nothing, sigma = nothing, all = false, return_sim =true, return_grad= false, supply = false)
        

        delta = something(delta, model.delta)
        sigma = something(sigma, model.sigma)


        # For each market we compute the random utility part
        v = -exp.(sigma .* model.errors);
        alphas = model.beta[end] .+ v;
        grad = zeros(model.T*model.J, 1);
        dc_dsigma = zeros(model.T * model.J, 1);
        dc_dbetap = zeros(model.T * model.J, 1);

        ds_dp = zeros(model.T * model.J, model.J);
        util = zeros(model.J * model.T, model.R);
        choice = zeros(model.J * model.T, model.R);
        util_price = zeros(model.J * model.T, model.R);
        ds_dsigma = zeros(model.T * model.J, model.R);
        cs_sim = zeros(model.T, 1);
        elas = zeros(model.T * model.J, model.J);
        cost_sim = zeros(model.T * model.J, 1);
        markup_sim = zeros(model.T * model.J, 1);

        for m_i in 1:model.T
            
            idx = (m_i - 1)* model.J + 1:m_i* model.J;
            util_price[idx, :] = model.p[idx,:] * v[m_i, :]';

            util[idx, :] .= delta[idx, :] .+ util_price[idx, :];
            choice[idx, :] .= exp.(util[idx, :]) ./ (1 .+ sum(exp.(util[idx, :]) , dims =1));

            if all
                for r_i in 1:model.R
                    pp_ = choice[idx, r_i];
                    pp = (diagm(pp_) - pp_ * pp_');
                    ds_dp[idx, :] += pp  * alphas[m_i, r_i]/model.R;
                end
                elas[idx, :] = ds_dp[idx, :] .* model.p[idx, :]' ./ model.shares[idx, :];

                # Recovering costs from ownership matrix
                if (model.Omega != zeros(model.J, model.J))
                    cost_sim[idx,:] = model.p[idx, :] + inv(model.Omega .* ds_dp[idx, :]) * model.shares[idx, :];
                else
                    cost_sim[idx,:] = model.p[idx, :]
                end
                markup_sim[idx, :] =  (model.p[idx, :] - cost_sim[idx,:]) ./ model.p[idx, :];
                cs_sim[m_i, 1] = mean(-log.(1 .+ sum(exp.(util[idx, :]), dims = 1)) ./ alphas[[m_i],:]);
            end


            if supply & (model.Omega != zeros(model.J, model.J))
                
                for r_i in 1:model.R
                    pp_ = choice[idx, r_i];
                    pp = (diagm(pp_) - pp_ * pp_');
                    ds_dp[idx, :] += pp  * alphas[m_i, r_i]/model.R;
                end
                cost_sim[idx,:] = model.p[idx, :] + inv(model.Omega .* ds_dp[idx, :]) * model.shares[idx, :];
                markup_sim[idx, :] =  (model.p[idx, :] - cost_sim[idx,:]) ./ model.p[idx, :];
 
            end
            

            if (return_grad | all)
                ds_ddelta = zeros(model.J, model.J);
                for r_i in 1:model.R
                    pp_ = choice[idx, r_i];
                    pp = (diagm(pp_) - pp_ * pp_');
                    dd = v[m_i, r_i] .* model.errors[m_i, r_i] ;
                    ds_ddelta += pp;
                    ds_dsigma[idx, r_i] = (pp * (dd .* model.p[idx, :]));
                end
                grad[idx, :] = - ((ds_ddelta  ./ (model.R)) \ mean(ds_dsigma[idx, :], dims = 2));

                if supply
                    A     = model.Omega .* ds_dp[idx, :]
                    Ainv  = Base.all(iszero, A) ? zero(A) : inv(A) # perfect competition: c = p, so dc/dθ = 0
                    s_idx = model.shares[idx, :]
                    dDelta = zeros(model.J, model.J)
                    for r_i in 1:model.R
                        s_r  = choice[idx, r_i]
                        S_r  = diagm(s_r) - s_r * s_r'
                        dd   = v[m_i, r_i] * model.errors[m_i, r_i]            # dα_r/dσ
                        ds_r = S_r * (grad[idx, :] + model.p[idx, :] .* dd)     # total dS/dσ, J×1
                        dS_r = diagm(vec(ds_r)) - ds_r * s_r' - s_r * ds_r'
                        dDelta += (dd .* S_r + alphas[m_i, r_i] .* dS_r) / model.R
                    end
                    dc_dsigma[idx, :] = -Ainv * (model.Omega .* dDelta) * (Ainv * s_idx)
                    dc_dbetap[idx, :] = -Ainv * (model.Omega .* (ds_ddelta ./ model.R)) * (Ainv * s_idx)
                end

            end
        end

        if (model.Omega == zeros(model.J, model.J))
            
            cost_sim = model.p
            markup_sim = (model.p - cost_sim) ./ model.p

        end

        
        # Store all the computations in the object

        if all
            model.elas_sim = elas;
            model.cost_sim = cost_sim;
            model.markup_sim = markup_sim;
            model.cs_sim = cs_sim;
            model.profit_sim = (model.p - model.cost_sim) .* model.shares;
            model.ps_sim = sum(reshape(model.profit_sim, (model.J, model.T)), dims = 1)'
            model.ts_sim = model.cs_sim + model.ps_sim
            model.shares_sim = mean(choice, dims = 2);
            model.grad = grad;
            model.alphas = alphas;
            model.util = util;
            model.choice = choice;
            model.delta = delta;
            model.ds_dp = ds_dp; # To compute diversion ratios
        end

        # Return the gradient
        if return_grad & !supply
            return grad
        end

        # Return the simulation
        if return_sim & !supply
            return mean(choice, dims = 2);
        end

        if return_grad & supply
            return grad, dc_dsigma, dc_dbetap
        end

        # Return the choice and cost return if supply is active
        if return_sim & supply
            return mean(choice, dims = 2), cost_sim
        end
    
    end

    # Fixed point algorithm
    function contraction(model, sigma_alpha; toler = 1e-10, max_iter = 10000, compute_grad = false)
        diff = 1000;
        delta = log.(model.shares) - log.(model.shares_0);
        flag = 0;
        count = 1;
        while toler < norm(diff)
            count += 1;
            shares_sim = simulate_BLP!(model, delta =  delta, sigma = sigma_alpha);
            diff = log.(model.shares) - log.(shares_sim);
            delta = delta + diff;
            if count > max_iter
                flag = -1;
                println("Reached max number of iterations"
                )
                break
                
            end
        end
        return delta
    end



    # Merger simulation

    function counterfactual_simulation(model_system::BLP; toler = 1e-8, max_iter = 10000, lambda = 0.1)

        # lambda: damping weight on the new price (the undamped iteration diverges)

        diff = 10
        model = model_system.BLPDemand
        p_sim = zeros(model.T * model.J, 1);
        cost_sim = model.cost_sim
        shares_sim = model.shares_sim
        count = 1
        flag = 0

        while toler < norm(diff)
            count += 1;

            # Initializing
            delta = model.X_all * model.beta + model.xi;
            ds_dp = zeros(model.T * model.J, model.J);
            util = zeros(model.J * model.T, model.R);
            choice = zeros(model.J * model.T, model.R);
            util_price = zeros(model.J * model.T, model.R);
            v = -exp.(model.sigma .* model.errors);
            alphas = model.beta[end] .+ v;

            # Given the shares, compute the new price

            for m_i in 1:model.T
                
                idx = (m_i - 1)* model.J + 1:m_i* model.J;
                util_price[idx, :] = model.p[idx,:] * v[m_i, :]';

                util[idx, :] .= delta[idx, :] .+ util_price[idx, :];
                choice[idx, :] .= exp.(util[idx, :]) ./ (1 .+ sum(exp.(util[idx, :]) , dims =1));

                for r_i in 1:model.R
                    pp_ = choice[idx, r_i];
                    pp = (diagm(pp_) - pp_ * pp_');
                    ds_dp[idx, :] += pp  * alphas[m_i, r_i]/model.R;
                end
                p_new = - inv(model.Omega .* ds_dp[idx, :]) * model.shares[idx, :] + cost_sim[idx,:];
                p_sim[idx, :] = lambda .* p_new .+ (1 - lambda) .* model.p[idx, :];
                
            end
            p_old = copy(model.p)
            # Replace the last element of the X_all matrix
            model.p = deepcopy(p_sim)
            model.X_all[:, end] = deepcopy(p_sim)
            model.delta = model.X_all * model.beta + model.xi;

            # Given the new price, compute the shares
            shares_sim = simulate_BLP!(model)            
        
            # Check convergence in prices
            diff = maximum(abs.(p_sim - p_old));

            # Chaging simulated shares and real shares
            model.shares = shares_sim
            model.shares_sim = shares_sim

            if count > max_iter
                flag = -1
                println("Reached max number of iterations"
                )
                break
            end

        end

        if flag == 0
            simulate_BLP!(model, all = true)
        end

        return model_system


    end



    # Objective function with the gradient
    function gmm_fg!(F, G, model, sigma; toler = 1e-10, max_iter = 10000)

        delta = contraction(model, sigma, toler = toler, max_iter = max_iter)
        e_xi = model.M * delta;

        if G !== nothing
            grad_ = simulate_BLP!(model, delta = delta, sigma = sigma, return_grad = true)
            G .= 2 * grad_' * model.Z * model.W *  model.Z' * e_xi;
        end
        if F !== nothing
            return ((model.Z' * e_xi)' * model.W  * model.Z' * e_xi)[]
        end

    end


    function compute_hausman(model)

        # Computing Hausman style instrument for price
        price_bar = zeros(model.J*model.T, 1)
        ts = sum(reshape(model.p, (model.J, model.T)), dims = 2)

        for m_i in 1: model.T
            idx = (m_i - 1)* model.J + 1:m_i* model.J
            price_bar[idx, :] = (ts - model.p[idx, :])/(model.T-1)

        end

        return price_bar

    end


    function compute_blp(model)

        X_rivals = zeros(model.J*model.T, model.k - 1)
        for m_i in 1:model.T
            idx = (m_i - 1) * model.J + 1: (m_i) * model.J
            X_rivals[idx, :] = (sum(model.X[idx, :], dims = 1) .- model.X[idx, :])
        end
        X_rivals = X_rivals[:, 2:end];
        return X_rivals

    end

    function estimate_blp!(model; Z = nothing, W = nothing, sigma_lower = 0.1, sigma_upper = 10, Ns = 10, toler = 1e-10, max_iter = 10000, iterations = 1000, time_limit = Inf, failures = nothing)
        
        model.Z = something(Z, model.Z);
        model.W = something(W, model.W);

        model.k_Z = size(model.Z, 2);
        model.M =  (I -  model.X_all * inv(model.X_all' * model.Z * model.W * model.Z' * model.X_all) * model.X_all'* model.Z * model.W * model.Z');
        

        # Seed globally
        Random.seed!(704)

        sigma0_ = clamp.(randn(Ns) * 0.5 .+ 1, sigma_lower, sigma_upper);

        
        function estimate_model(sigma0)

            t0 = time()
            try
                res = optimize(NLSolversBase.only_fg!((F, G, s) -> blp.gmm_fg!(F, G, model, s, toler = toler, max_iter = max_iter)), [sigma_lower], [sigma_upper], [sigma0], Fminbox(LBFGS()), Optim.Options(iterations = iterations, time_limit = time_limit))
                println("  start sigma0 = $(round(sigma0, digits = 3)) -> sigma = $(round(Optim.minimizer(res)[1], digits = 4)), obj = $(Optim.minimum(res)), $(round(time() - t0, digits = 1))s"); flush(stdout)
                return res
            catch err
                msg = sprint(showerror, err)
                println("  start sigma0 = $(round(sigma0, digits = 3)) FAILED after $(round(time() - t0, digits = 1))s: $(first(msg, 120))"); flush(stdout)
                failures === nothing || push!(failures, (sigma0 = sigma0, error = msg))
                return nothing
            end

        end
        
        ress = collect(Any, filter(!isnothing, estimate_model.(sigma0_)));

        idmin = argmin(Optim.minimum.(ress));
        optimized = ress[idmin];

        sigma_est = Optim.minimizer(optimized)[1];
        model.sigma = sigma_est
        # Get the estimates for delta
        delta = blp.contraction(model, model.sigma);
        # Get the estimates for beta
        beta_est =  inv(model.X_all' * model.Z * model.W * model.Z' * model.X_all) * model.X_all'* model.Z * model.W * model.Z' * delta;

        model.delta = delta;
        model.xi = model.M * model.delta;
        model.beta = beta_est;
        model.opt_res = ress
        model.params = vcat(beta_est, [sigma_est])
        blp.simulate_BLP!(model, all = true);

        omega_var = zeros(model.k_Z, model.k_Z)

        for jt_i in 1: model.T * model.J
            omega_var += 1/(model.J * model.T) * (model.xi[jt_i]^2) * model.Z[jt_i,:] * model.Z[jt_i,:]'
        end

        Gamma = 1/(model.J * model.T) * model.Z' * hcat(-model.X_all, model.grad);
        Var = inv(Gamma' * model.W * Gamma) * Gamma' * model.W * omega_var * model.W * Gamma * inv(Gamma' * model.W * Gamma) / (model.J * model.T);

        model.Var = Var

    end


    function gmm_joint_fg!(F, G, model, sigma; toler = 1e-10, max_iter = 10000)

        delta = blp.contraction(model.BLPDemand, sigma, toler = toler, max_iter = max_iter);
        # Update beta before computing cost
        model.BLPDemand.beta = inv(model.BLPDemand.X_all' * model.BLPDemand.Z * model.BLPDemand.W * model.BLPDemand.Z' * model.BLPDemand.X_all) * model.BLPDemand.X_all'* model.BLPDemand.Z * model.BLPDemand.W * model.BLPDemand.Z' * delta;
        shares, cost = blp.simulate_BLP!(model.BLPDemand, delta = delta, sigma = sigma, supply = true);
        model.BLPSupply.beta = inv(model.BLPSupply.X' * model.BLPSupply.Z * model.BLPSupply.W * model.BLPSupply.Z' * model.BLPSupply.X) * model.BLPSupply.X'* model.BLPSupply.Z * model.BLPSupply.W * model.BLPSupply.Z' * cost;
        e_xi = model.BLPDemand.M * delta;
        e_omega = model.BLPSupply.M * cost;
        moments = [model.BLPDemand.Z' * e_xi;
                model.BLPSupply.Z' * e_omega;
                ]
        W_g = BlockDiagonal([model.BLPDemand.W, model.BLPSupply.W]);

        # Initialize beta properly in the demand side to compute the gradient properly
        

        if G !== nothing
            
            grad_, dc_dsigma_, dc_dbetap_ = blp.simulate_BLP!(model.BLPDemand, delta = delta, sigma = sigma, return_grad = true, supply = true);
            B = inv(model.BLPDemand.X_all' * model.BLPDemand.Z * model.BLPDemand.W * model.BLPDemand.Z' * model.BLPDemand.X_all) * model.BLPDemand.X_all' * model.BLPDemand.Z * model.BLPDemand.W * model.BLPDemand.Z';
            dc_dsigma_total = dc_dsigma_ .+ dc_dbetap_ .* ((B * grad_)[end]) # We need to add the impact of the change of sigma in the cost through changes in beta
            G_demand = 2 * grad_' * model.BLPDemand.Z * model.BLPDemand.W *  model.BLPDemand.Z' * e_xi;
            G_supply = 2 * dc_dsigma_total' * model.BLPSupply.Z * model.BLPSupply.W *  model.BLPSupply.Z' * e_omega;
            G .= G_demand + G_supply

        end

        if F !== nothing
            return (moments' * W_g * moments)[]
        end
    
    end

    function estimate_blp_joint!(model; sigma_lower = 0.1, sigma_upper = 10, Ns = 10, toler = 1e-10, max_iter = 10000, iterations = 100, time_limit = Inf, failures = nothing)
        # Seed globally
        Random.seed!(704)

        sigma0_ = clamp.(randn(Ns) * 0.5 .+ 1, sigma_lower, sigma_upper);

        
        function estimate_model(sigma0)
            t0 = time()
            try
                res = optimize(NLSolversBase.only_fg!((F, G, s) -> gmm_joint_fg!(F, G, model, s, toler = toler, max_iter = max_iter)), 
                               [sigma_lower], [sigma_upper], [sigma0], Fminbox(LBFGS()),
                                Optim.Options(
                                    iterations = iterations,
                                    time_limit = time_limit
                                    )
                                )
                println("  start sigma0 = $(round(sigma0, digits = 3)) -> sigma = $(round(Optim.minimizer(res)[1], digits = 4)), obj = $(Optim.minimum(res)), $(round(time() - t0, digits = 1))s"); flush(stdout)
                return res
            catch err
                msg = sprint(showerror, err)
                println("  start sigma0 = $(round(sigma0, digits = 3)) FAILED after $(round(time() - t0, digits = 1))s: $(first(msg, 120))"); flush(stdout)
                failures === nothing || push!(failures, (sigma0 = sigma0, error = msg))
                return nothing
            end
        end

        ress = collect(Any, filter(!isnothing, estimate_model.(sigma0_)));
        
        idmin = argmin(Optim.minimum.(ress));
        optimized = ress[idmin];
        sigma_est = Optim.minimizer(optimized)[1];
        model.BLPDemand.sigma = sigma_est
        # Get the estimates for delta
        delta = blp.contraction(model.BLPDemand, model.BLPDemand.sigma);

        # Get the estimates for beta
        blp.simulate_BLP!(model.BLPDemand, all = true);

        beta_est =  inv(model.BLPDemand.X_all' * model.BLPDemand.Z * model.BLPDemand.W * model.BLPDemand.Z' * model.BLPDemand.X_all) * model.BLPDemand.X_all'* model.BLPDemand.Z * model.BLPDemand.W * model.BLPDemand.Z' * model.BLPDemand.delta;
        beta_supply =inv(model.BLPSupply.X' * model.BLPSupply.Z * model.BLPSupply.W * model.BLPSupply.Z' * model.BLPSupply.X) * model.BLPSupply.X'* model.BLPSupply.Z * model.BLPSupply.W * model.BLPSupply.Z' * model.BLPDemand.cost_sim;

        model.BLPDemand.delta = delta;
        model.BLPDemand.xi = model.BLPDemand.M * model.BLPDemand.delta;
        model.BLPDemand.beta = beta_est;
        model.BLPDemand.opt_res = ress

        model.BLPSupply.beta = beta_supply;

        
        d, s = model.BLPDemand, model.BLPSupply
        N  = d.T * d.J
        kb = size(d.X_all, 2)       # demand linear params (price is the last one)
        kc = size(s.X, 2)           # cost shifters
        kd = size(d.Z, 2)
        ks = size(s.Z, 2)

        # Everything evaluated at the estimates
        grad, dc_dsigma, dc_dbetap = blp.simulate_BLP!(d, delta = d.delta, sigma = d.sigma, return_grad = true, supply = true)
        _, cost = blp.simulate_BLP!(d, delta = d.delta, sigma = d.sigma, supply = true)

        xi    = d.M * d.delta       # demand residual
        omega = s.M * cost          # supply residual

        # Jacobians of the residuals wrt θ = [β; γ; σ]
        dxi    = hcat(-d.X_all, zeros(N, kc), grad)
        domega = hcat(zeros(N, kb - 1), dc_dbetap, -s.X, dc_dsigma)

        # Γ = ∂ĝ/∂θ'
        Gamma = vcat(d.Z' * dxi, s.Z' * domega) ./ N

        # Moment covariance (full, keeps the ξ–ω cross block)
        g = hcat(d.Z .* xi, s.Z .* omega)               # N × (kd + ks)
        
        S = g' * g ./ N

        Wg = [d.W zeros(kd, ks); zeros(ks, kd) s.W]
        B  = inv(Gamma' * Wg * Gamma)
        V  = B * Gamma' * Wg * S * Wg * Gamma * B ./ N


        model.params = vcat( model.BLPDemand.beta, model.BLPSupply.beta, [sigma_est])
        model.Var = V

    end


    

end

