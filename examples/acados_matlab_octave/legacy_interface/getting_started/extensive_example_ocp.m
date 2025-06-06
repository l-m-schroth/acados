%
% Copyright (c) The acados authors.
%
% This file is part of acados.
%
% The 2-Clause BSD License
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%
% 1. Redistributions of source code must retain the above copyright notice,
% this list of conditions and the following disclaimer.
%
% 2. Redistributions in binary form must reproduce the above copyright notice,
% this list of conditions and the following disclaimer in the documentation
% and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.;



% NOTE: `acados` currently supports both an old MATLAB/Octave interface (< v0.4.0)
% as well as a new interface (>= v0.4.0).

% THIS EXAMPLE still uses the OLD interface. If you are new to `acados` please start
% with the examples that have been ported to the new interface already.
% see https://github.com/acados/acados/issues/1196#issuecomment-2311822122)

clear all; clc;

addpath('../pendulum_on_cart_model')

check_acados_requirements()

print_level = 1;

%% discretization
N = 40;
T = 2.0; % time horizon length
h = T/N;

% nonuniform time grid
% N1 = 5;
% N2 = N - N1;
% time_steps = [( 1 * ones(N1,1)); 3 * ones(N2,1)];
% time_steps = T/sum(time_steps) * time_steps;

% uniform time grid
time_steps = T/N * ones(N,1);

shooting_nodes = zeros(N+1, 1);
for i = 1:N
    shooting_nodes(i+1) = sum(time_steps(1:i));
end

nlp_solver = 'sqp'; % sqp, sqp_rti
nlp_solver_exact_hessian = 'false';
regularize_method = 'convexify';
     % no_regularize, project, project_reduc_hess, mirror, convexify
nlp_solver_max_iter = 50;
tol = 1e-8;
qp_solver = 'partial_condensing_hpipm';
    % full_condensing_hpipm, partial_condensing_hpipm
    % full_condensing_qpoases, partial_condensing_osqp
qp_solver_cond_N = 5; % for partial condensing
qp_solver_cond_ric_alg = 0;
qp_solver_ric_alg = 0;
qp_solver_warm_start = 1; % 0: cold, 1: warm, 2: hot
qp_solver_iter_max = 1000; % default is 50; OSQP needs a lot sometimes.
qp_solver_mu0 = 1e4;

% can vary for integrators
sim_method_num_stages = 1 * ones(N,1);
sim_method_num_steps = ones(N,1);
sim_method_num_stages(3:end) = 2;

%% model dynamics
model = pendulum_on_cart_model();

%% model to create the solver
ocp_model = acados_ocp_model();

%% dimensions
nx = model.nx;
nu = model.nu;

model_name = 'pendulum';

%% cost formulation
cost_formulation = 1;
switch cost_formulation
    case 1
        cost_type = 'linear_ls';
    case 2
        cost_type = 'ext_cost';
    otherwise
        cost_type = 'auto';
end

%% integrator type
integrator = 1;
switch integrator
    case 1
        sim_method = 'erk';
    case 2
        sim_method = 'irk';
    case 3
        sim_method = 'discrete';
    otherwise
        sim_method = 'irk_gnsf';
end

%% cost
ocp_model.set('cost_type_0', cost_type);
ocp_model.set('cost_type', cost_type);
ocp_model.set('cost_type_e', cost_type);
if strcmp( cost_type, 'linear_ls' )
    ocp_model.set('cost_Vu_0', model.cost_Vu_0);
    ocp_model.set('cost_Vx_0', model.cost_Vx_0);
    ocp_model.set('cost_W_0', model.cost_W_0);
    ocp_model.set('cost_y_ref_0', model.cost_y_ref_0);

    ocp_model.set('cost_Vu', model.cost_Vu);
    ocp_model.set('cost_Vx', model.cost_Vx);
    ocp_model.set('cost_W', model.cost_W);
    ocp_model.set('cost_y_ref', model.cost_y_ref);

    ocp_model.set('cost_Vx_e', model.cost_Vx_e);
    ocp_model.set('cost_W_e', model.cost_W_e);
    ocp_model.set('cost_y_ref_e', model.cost_y_ref_e);
else % external, auto
    ocp_model.set('cost_expr_ext_cost_0', model.cost_expr_ext_cost_0);
    ocp_model.set('cost_expr_ext_cost', model.cost_expr_ext_cost);
    ocp_model.set('cost_expr_ext_cost_e', model.cost_expr_ext_cost_e);
end

%% constraints
constraint_formulation_nonlinear = 0;
lbu = -80*ones(nu, 1);
ubu =  80*ones(nu, 1);
if constraint_formulation_nonlinear % formulate constraint via h
    ocp_model.set('constr_expr_h_0', model.expr_h_0);
    ocp_model.set('constr_lh_0', lbu);
    ocp_model.set('constr_uh_0', ubu);
    ocp_model.set('constr_expr_h', model.expr_h);
    ocp_model.set('constr_lh', lbu);
    ocp_model.set('constr_uh', ubu);
else % formulate constraint as bound on u
    Jbu = eye(nu);
    ocp_model.set('constr_Jbu', Jbu);
    ocp_model.set('constr_lbu', lbu);
    ocp_model.set('constr_ubu', ubu);
end

%% acados ocp model
ocp_model.set('name', model_name);
ocp_model.set('T', T);

% symbolics
ocp_model.set('sym_x', model.sym_x);
if isfield(model, 'sym_u')
    ocp_model.set('sym_u', model.sym_u);
end
if isfield(model, 'sym_xdot')
    ocp_model.set('sym_xdot', model.sym_xdot);
end
if isfield(model, 'sym_z') % algebraic variables
    ocp_model.set('sym_z', model.sym_z);
end
if isfield(model, 'sym_p') % parameters
    ocp_model.set('sym_p', model.sym_p);
end

% dynamics
if (strcmp(sim_method, 'erk'))
    ocp_model.set('dyn_type', 'explicit');
    ocp_model.set('dyn_expr_f', model.dyn_expr_f_expl);
elseif (strcmp(sim_method, 'irk') || strcmp(sim_method, 'irk_gnsf'))
    ocp_model.set('dyn_type', 'implicit');
    ocp_model.set('dyn_expr_f', model.dyn_expr_f_impl);
elseif strcmp(sim_method, 'discrete')
    ocp_model.set('dyn_type', 'discrete');
    % build explicit euler discrete integrator
    import casadi.*
    expl_ode_fun = Function([model_name,'_expl_ode_fun'], ...
            {model.sym_x, model.sym_u}, {model.dyn_expr_f_expl});
    dyn_expr_phi = model.sym_x + T/N * expl_ode_fun(model.sym_x, model.sym_u);
    ocp_model.set('dyn_expr_phi', dyn_expr_phi)
    if ~all(time_steps == T/N)
        disp('nonuniform time discretization with discrete dynamics should not be used');
        keyboard
    end
end

% initial state
x0 = [0; pi; 0; 0];
ocp_model.set('constr_x0', x0);

%% acados ocp set opts
ocp_opts = acados_ocp_opts();
ocp_opts.set('param_scheme_N', N);
if (exist('time_steps', 'var'))
	ocp_opts.set('time_steps', time_steps);
end

ocp_opts.set('nlp_solver', nlp_solver);
ocp_opts.set('nlp_solver_exact_hessian', nlp_solver_exact_hessian);
ocp_opts.set('regularize_method', regularize_method);
if (strcmp(nlp_solver, 'sqp')) % not available for sqp_rti
    ocp_opts.set('nlp_solver_max_iter', nlp_solver_max_iter);
    ocp_opts.set('nlp_solver_tol_stat', tol);
    ocp_opts.set('nlp_solver_tol_eq', tol);
    ocp_opts.set('nlp_solver_tol_ineq', tol);
    ocp_opts.set('nlp_solver_tol_comp', tol);
end
ocp_opts.set('qp_solver', qp_solver);
ocp_opts.set('qp_solver_cond_N', qp_solver_cond_N);
ocp_opts.set('qp_solver_ric_alg', qp_solver_ric_alg);
ocp_opts.set('qp_solver_cond_ric_alg', qp_solver_cond_ric_alg);
ocp_opts.set('qp_solver_warm_start', qp_solver_warm_start);
ocp_opts.set('qp_solver_iter_max', qp_solver_iter_max);
ocp_opts.set('qp_solver_mu0', qp_solver_mu0);
ocp_opts.set('sim_method', sim_method);
ocp_opts.set('sim_method_num_stages', sim_method_num_stages);
ocp_opts.set('sim_method_num_steps', sim_method_num_steps);

ocp_opts.set('exact_hess_dyn', 1);
ocp_opts.set('exact_hess_cost', 1);
ocp_opts.set('exact_hess_constr', 1);
ocp_opts.set('print_level', print_level);

%% create ocp solver
ocp_solver = acados_ocp(ocp_model, ocp_opts);

% state and input initial guess
x_traj_init = zeros(nx, N+1);
x_traj_init(2, :) = linspace(pi, 0, N+1); % initialize theta

u_traj_init = zeros(nu, N);

%% prepare evaluation
n_executions = 1;
time_tot = zeros(n_executions,1);
time_lin = zeros(n_executions,1);
time_reg = zeros(n_executions,1);
time_qp_sol = zeros(n_executions,1);

%% call ocp solver in loop
for i=1:n_executions
    % initial state
    ocp_solver.set('constr_x0', x0);

    % set trajectory initialization
    ocp_solver.set('init_x', x_traj_init);
    ocp_solver.set('init_u', u_traj_init);
    ocp_solver.set('init_pi', zeros(nx, N)); % multipliers for dynamics equality constraints

    % solve
    ocp_solver.solve();
    % get solution
    utraj = ocp_solver.get('u');
    xtraj = ocp_solver.get('x');

    % evaluation
    status = ocp_solver.get('status');
    sqp_iter = ocp_solver.get('sqp_iter');
    time_tot(i) = ocp_solver.get('time_tot');
    time_lin(i) = ocp_solver.get('time_lin');
    time_reg(i) = ocp_solver.get('time_reg');
    time_qp_sol(i) = ocp_solver.get('time_qp_sol');

    if i == 1 || i == n_executions
        ocp_solver.print('stat')
    end
end

% get slack values
for i = 0:N-1
    sl = ocp_solver.get('sl', i);
    su = ocp_solver.get('su', i);
end
sl = ocp_solver.get('sl', N);
su = ocp_solver.get('su', N);

% get cost value
cost_val_ocp = ocp_solver.get_cost();


%% get QP matrices:
% See https://docs.acados.org/problem_formulation
%        |----- dynamics -----|------ cost --------|---------------------------- constraints ------------------------|
fields = {'qp_A','qp_B','qp_b','qp_R','qp_Q','qp_r','qp_C','qp_D','qp_lg','qp_ug','qp_lbx','qp_ubx','qp_lbu','qp_ubu'};
% either stage wise
for stage = [0,N-1]
    for k = 1:length(fields)
        field = fields{k};
        disp(strcat(field, " at stage ", num2str(stage), " = "));
        ocp_solver.get(field, stage)
    end
end

stage = N;
field = 'qp_Q';
disp(strcat(field, " at stage ", num2str(stage), " = "));
ocp_solver.get(field, stage)
field = 'qp_R';
disp(strcat(field, " at stage ", num2str(stage), " = "));
ocp_solver.get(field, stage)

% or for all stages
qp_Q = ocp_solver.get('qp_Q');
cond_H = ocp_solver.get('qp_solver_cond_H');

disp('QP diagnostics of last QP before condensing')
result = ocp_solver.qp_diagnostics(false);
disp(['min eigenvalues of blocks are in [', num2str(min(result.min_eigv_stage)), ', ', num2str(max(result.min_eigv_stage)), ']'])
disp(['max eigenvalues of blocks are in [', num2str(min(result.max_eigv_stage)), ', ', num2str(max(result.max_eigv_stage)), ']'])
disp(['condition_number_stage: '])
disp(result.condition_number_stage)
disp(['condition_number_global: ', num2str(result.condition_number_global)])

disp('QP diagnostics of last QP after partial condensing')
result = ocp_solver.qp_diagnostics(true);
disp(['min eigenvalues of blocks are in [', num2str(min(result.min_eigv_stage)), ', ', num2str(max(result.min_eigv_stage)), ']'])
disp(['max eigenvalues of blocks are in [', num2str(min(result.max_eigv_stage)), ', ', num2str(max(result.max_eigv_stage)), ']'])
disp(['condition_number_stage: '])
disp(result.condition_number_stage)
disp(['condition_number_global: ', num2str(result.condition_number_global)])

%% Plot trajectories
figure; hold on;
States = {'p', 'theta', 'v', 'dtheta'};
for i=1:length(States)
    subplot(length(States), 1, i);
    plot(shooting_nodes, xtraj(i,:)); grid on;
    ylabel(States{i});
    xlabel('t [s]')
end

figure
stairs(shooting_nodes, [utraj'; utraj(end)])

ylabel('F [N]')
xlabel('t [s]')
grid on
if is_octave()
    waitforbuttonpress;
end

%% plot average compuation times
% if ~is_octave()
%     time_total = sum(time_tot);
%     time_linearize = sum(time_lin);
%     time_regulariz = sum(time_reg);
%     time_qp_solution = sum(time_qp_sol);
%
%     figure;
%
%     bar_vals = 1000 * [time_linearize; time_regulariz; time_qp_solution; ...
%         time_total - time_linearize - time_regulariz - time_qp_solution] / n_executions;
%     bar([1; nan], [bar_vals, nan(size(bar_vals))]' ,'stacked')
%     legend('linearization', 'regularization', 'qp solution', 'remaining')
%     ylabel('time in [ms]')
%     title( [ strrep(cost_type, '_',' '), ' , sim: ' strrep(sim_method, '_',' '), ...
%        ';  ', strrep(qp_solver, '_', ' ')] )
% end
