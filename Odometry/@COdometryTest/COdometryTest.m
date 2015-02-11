classdef COdometryTest < handle
    %COdometryTest Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(SetAccess=private)
        % Default initial values
        cam_sd = 0;
        lin_sd = 0;
        cube_sd = 0;
        rig_ini = 'rig.ini';
        pose_gen_ini = 'pose_gen.ini';
    end
        
    properties
        WITH_ELQURSH = true;
        WITH_TRIHEDRON = true;
        WITH_PLOT = true;
        WITH_COVARIANCE = false;
        WITH_DEBUG = false;
        
        WITH_KDE = false;
        
        TRICK_REMOVE_OUTLIERS_R = false;
        TRICK_REMOVE_OUTLIERS_t = false;
        
        % Stored variables
        Rrel % Relative rotation from Cam1 to Cam2, (^c1)R(_c2) (seen from Cam1 mobile axes)
        trel % Relative translation from Cam1 to Cam2, (^c1)t(_c2) (seen from Cam1 mobile axes)
        % Parameters for random generation
        Rrel_sd = 1;   % Angular magnitude (in [deg]) of random rotation matrix
        trel_sd = 0.5; % Distance (in [m]) of random translation vector
        
        % Temporary objects
        prim2D % 2D primitive
        
        % Graphic handles
        hFigure
        hF_scene
        hF_image
        
        % Used objects
        poseFactory
        Cam
        Cube
    end
    
    methods
        function this = COdometryTest( WITH_PLOT,...
                cam_sd, cube_sd,...
                rig_ini, pose_gen_ini ) %#ok<INUSD>
            
            setConstructorInputs;
            
            % Read camera  options
%             rig_config_file = fullfile( pwd, this.rig_ini );
%             rigOpts = readConfigFile( rig_config_file );
%             extractStructFields( rigOpts );
            % Set symbolic camera
            K =  [700 0 320 ; % 700
                  0 700 240 ;
                      0 0 1 ];
            res = [640 480];
            f = 0.2;
                  
            % Generate random pose for camera
            gen_conf_F = fullfile( pwd, this.pose_gen_ini );
            this.poseFactory = CRandomPoses( readConfigFile( gen_conf_F,'[Vanishing]' ) );
            % Set canonical pose as default 
            [R_w_c, t_w_c] = this.poseFactory.gen(1);
            
            % Generate random relative rotation among frames #1 and #2
            this.Rrel = expmap( deg2rad(randn(3,1)) ); % 1[deg] sd
            this.trel = 0.5*randn(3,1); % 50 cm sd
            
            % Create simulated camera
            this.Cam = CSimCamera( R_w_c, t_w_c, K, res, f, this.cam_sd );
            
            % Create pattern
            this.Cube = CHalfCube( 1, eye(3), zeros(3,1), this.cube_sd );
            
            if this.WITH_PLOT
                this.hFigure  = figure;
                this.hF_scene = subplot(1,2,1);
                this.Cube.plotScene(this.Cam);
                
                this.hF_image = subplot(1,2,2); hold on;
            end
        end
        
        function set.WITH_PLOT( this, value )
            this.WITH_PLOT = value;
            if ( value ) % Activation case
                this.hFigure  = figure;
                this.hF_scene = subplot(1,2,1);
                this.Cube.plotScene(this.Cam);
                
                this.hF_image = subplot(1,2,2); hold on;
            else % Deactivation case
%                 close all
            end
        end        
        function clearFigures( this )
            cla(this.hF_scene);
            cla(this.hF_image);
        end
        
        function update( this, prop, val )
            % Optional arguments:
            %   d - set distance of absolute pose to origin as d
            
            switch prop
                case 'd'
                    % Fix camera distance to cube
                    this.poseFactory.min_d = val;
                    this.poseFactory.max_d = val;
                case 'cam_sd'
                    % Fix pixel noise in camera
                    this.Cam.sd = val;
                case 'cube_sd'
                    % Fix pixel noise in 3D cube model
%                     L = this.Cube.L;
%                     R = this.Cube.R;
%                     t = this.Cube.t;
%                     new_sd = val;
%                     this.Cube = CHalfCube( L, R, t, new_sd );
                    this.Cube.sd = val;
                case 'FOV'
                    % Fix K
                    K = this.Cam.K;
                    K(1,1) = val;
                    K(2,2) = val;
                    this.Cam.K = K;
                case 'persp' % Test perspective distortion
                    M = 0.01; % Transverse magnification
                    f = val;
                    s0 = -0.20 + f * ( 1 + 1/M );
                    % Fix object distance
                    pf_config.min_d = s0;
                    pf_config.max_d = s0;
                    pf_config.min_ang = 30;
                    pf_config.ang_z_max = 0;
                    pf_config.ang_x_max = 0;
                    pf_config.ang_y_max = 0;
                    pf_config.device = 'Camera';
                    this.poseFactory = CRandomPoses( pf_config );
                    % Fix K
                    K = this.Cam.K;
                    K(1,1) = f * 2e4; % For Blender config!
                    K(2,2) = f * 2e4; % For Blender config!
                    this.Cam.K = K;
                case 'Rrel_sd'
                    this.Rrel_sd = val;
                case 'trel_sd'
                    this.trel_sd = val;
                case 'num'
                    % Do nothing, just for histogram
                otherwise
                    error('Not valid option %s for update',prop);
            end
        end
        function updatePose( this, updateCube )
            % updatePose( this, d )
            % Method for updating the camera pose in first octant
            % Absolute pose is produced through CRandomPoses
            % Relative pose is computed with SO(3) exp map and linear map
            % of random 3x1 vectors for rotation and translation, respectively

            % Create new pose for camera (wrt World reference)
            [R_w_c, t_w_c] = this.poseFactory.gen( 1 );
            % Assign new camera pose
            this.Cam.R = R_w_c;
            this.Cam.t = t_w_c;
            
            % Create new small relative transformation
%             this.Rrel = expmap( this.Rrel_sd*deg2rad(randn(3,1)) );
%             this.trel = this.trel_sd * randn(3,1);
            this.Rrel = expmap( this.Rrel_sd*deg2rad(-1+2*rand(3,1)) );
%             this.trel = this.trel_sd * (-1+2*rand(3,1));
            % Make trel proportional to abs t
            this.trel = this.trel_sd * 0.5*this.poseFactory.min_d * (-1+2*rand(3,1));
                        
            if ~exist('updateCube','var')
                updateCube = false;
            end
            % If control variable updateCube is true, update cube with
            % its 3D noise level
            if updateCube
                this.Cube.updateNoise;
            end
            
            if this.WITH_PLOT
                subplot(this.hF_scene);
                this.Cube.plotScene(this.Cam);
            end
        end
        
        function [err_elqursh, global_err_elqursh,...
                  err_P3oA, global_err_P3oA,...
                  global_err_P3oA_W] = ...
                  compareSingleCubeResults( this )
            [err_elqursh, global_err_elqursh] = this.syntheticElqursh;
            [err_P3oA, global_err_P3oA, global_err_P3oA_W] = this.syntheticP3oA;
            
            % Plot results
            h_ = figure;
            title('Error histogram'); hold on;
            
            subplot(1,2,1); hold on;
            plot(1, err_elqursh, '*b');
            plot(2, err_P3oA, '*g');
            ax = axis; axis([0 3 ax(3:4)]);
            
            subplot(1,2,2); hold on;
            hist( err_elqursh, 20, 0:0.1:10 );
            hist( err_P3oA, 0:0.1:10 );
            h = findobj(gca,'Type','patch');
            set(h(2),'FaceColor','b','EdgeColor','k');
            set(h(1),'FaceColor','g','EdgeColor','k');
            
            set(h_,'units','normalized','outerposition',[0 0 1 1]);
        end
        
        function [err_R, Cval] = test( this, method, arr_x, Nsim )         
            Nx = numel(arr_x);
%             err = repmat( struct('R',[],'t',[]), Nsim, Nx );
            err_R = repmat( struct('P3oA',[],'Elqu',[]), Nsim, Nx );
            Cval = cell(1,Nx);
            
            expState = CExperimentState( Nx*Nsim );
            for jj = 1:Nx
                % Print progress bar:
%                 fprintf('|%s|\n',repmat('-',1,Nsim));
%                 fprintf('|');
                x = arr_x(jj); % Set X axis parameter
%                 method( x );
                this.update( method, x );
                for ii = 1:Nsim
%                     fprintf('+');
                    withUpdateCube = strcmp(method,'cube_sd');
                    this.updatePose( withUpdateCube ); % Update in each iteration
%                     err(ii,jj) = this.syntheticOdometry;
                    try
                        err_R(ii,jj) = this.syntheticOrientation;
                    catch exception
                        disp(exception.message);
                        for kstack=1:numel(exception.stack)
                            disp(exception.stack(kstack));
                        end
                        fields = fieldnames(err_R);
                        for k=1:numel(fields)
                            f = fields{k};
                            err_R(ii,jj).(f) = NaN;
                        end
                    end
                    % Print status
                    expState.update;
                end
%                 fprintf('|\n');
%                 Cval{jj} = num2str( x ); % Store tag for X axis value
            end
            % Other more compact option
            Cval = cellfun(@num2str,num2cell(arr_x),'UniformOutput',false);
            
            % Store simulation data
            file = datestr(now);
            file = strrep( file,'-','_' );
            file = strrep( file,' ','_' );
            file = strrep( file,':','_' );
            file = ['test_',method,'_',file,'.mat'];
            file = fullfile(pwd,'Odometry','store',file);
            save( file, 'err_R', 'method', 'Cval' );
            
            this.testPlot( err_R, Cval );
        end
                
        function test_Math( this, method, arr_x, Nsim )
            Nx = numel(arr_x);
           
            err_Elqu = cell(Nsim,Nx);
            err_P3oA    = cell(Nsim,Nx);
            
            expState = CExperimentState( Nx*Nsim );
            for jj = 1:Nx
                % Print progress bar:
%                 fprintf('|%s|\n',repmat('-',1,Nsim));
%                 fprintf('|');
                x = arr_x(jj); % Set X axis parameter
%                 method( x );
                this.update( method, x );
                for ii = 1:Nsim
%                     fprintf('+');
                    withUpdateCube = strcmp(method,'cube_sd');
                    this.updatePose( withUpdateCube ); % Update in each iteration
                    try
                        [err_Elqu{ii,jj}, ~] = this.syntheticElqursh;
                        [err_P3oA{ii,jj}, ~, ~] = this.syntheticP3oA;
                    catch exception
                        disp(exception.message);
                        for kstack=1:numel(exception.stack)
                            disp(exception.stack(kstack));
                        end
                        fields = fieldnames(err_R);
                        for k=1:numel(fields)
                            f = fields{k};
                            err_R(ii,jj).(f) = NaN;
                        end
                    end
                    % Print status
                    expState.update;
                end
%                 fprintf('|\n');
%                 Cval{jj} = num2str( x ); % Store tag for X axis value
            end
            % Other more compact option
            Cval = cellfun(@num2str,num2cell(arr_x),'UniformOutput',false);
           
            % Transpose cell contents
            err_Elqu = cellfun( @transpose, err_Elqu, 'UniformOutput',false );
            err_P3oA = cellfun( @transpose, err_P3oA, 'UniformOutput',false );

            % Create matrix of stacked data:
            M_P3oA = cell2mat(err_P3oA);
            M_Elqu = cell2mat(err_Elqu);
            s = max( size(M_P3oA,1), size(M_Elqu,1) );
            M_P3oA(end+1:s,:) = NaN;
            M = [M_P3oA, M_Elqu];
            
            % Store simulation data
            file = datestr(now);
            file = strrep( file,'-','_' );
            file = strrep( file,' ','_' );
            file = strrep( file,':','_' );
            file = ['test_Math_',method,'_',file,'.mat'];
            file = fullfile(pwd,'Odometry','store',file);
            save( file, 'M', 'method', 'Cval' );
            
            % Plot histogram
            switch method
                case 'num'
                    this.testPlotHist( M );
                otherwise
                    this.testPlot( M, Cval );
            end
        end
        
        function [err_elqursh, global_err_elqursh,...
                  err_P3oA, global_err_P3oA,...
                  global_err_P3oA_W] = ...
                  compareSeveralCubeResults( this, Nsim )
            err_elqursh = cell(Nsim,1);
            err_P3oA = cell(Nsim,1);
            global_err_elqursh = zeros(1,Nsim);
            global_err_P3oA = zeros(1,Nsim);
            global_err_P3oA_W = zeros(1,Nsim);
            for ii = 1:Nsim
                this.updatePose;
                
                [err_elqursh{ii}, global_err_elqursh(ii)] = ...
                    this.syntheticElqursh;
                [err_P3oA{ii}, global_err_P3oA(ii), temp] = ...
                    this.syntheticP3oA;
                if ~isempty(temp)
                    global_err_P3oA_W(ii) = temp;
                end
            end
            % Linearize all values
            err_elqursh = [err_elqursh{:}];
            err_P3oA = [err_P3oA{:}];
            
            if nargout == 0
                % Store simulation data
                file = datestr(now);
                file = strrep( file,'-','_' );
                file = strrep( file,' ','_' );
                file = strrep( file,':','_' );
                file = ['Several_',file,'.mat'];
                file = fullfile(pwd,'Odometry','store',file);
                save(file, 'err_elqursh','global_err_elqursh',...
                    'err_P3oA','global_err_P3oA','global_err_P3oA_W' );
                
                this.plotSeveralCubeResults(...
                    err_elqursh, global_err_elqursh,...
                    err_P3oA, global_err_P3oA, global_err_P3oA_W );
            end
        end
        
        function err = compareSyntheticOdometry( this, Nsim )
            
            fields  = {'P3oA','Elqu','Fuse'};
            Nfields = numel(fields);
            err = repmat( struct('P3oA',[],'Elqu',[],'Fuse',[]), 1, Nsim );
            for ii = 1:Nsim
                this.updatePose;
                err_ = this.syntheticOdometry;
                for k = 1:Nfields
                    f = fields{k};
                    err(ii).(f) = err_.R.(f);
                end
            end
            all_err = [ [err.P3oA]
                        [err.Elqu]
                        [err.Fuse] ]';
            % Plot results statistics
            boxplot( all_err );
        end
        function err = compareSyntheticOrientation( this, Nsim )
            fields  = {'P3oA','Elqu','Fuse'};
            Nfields = numel(fields);
            err = repmat( struct('P3oA',[],'Elqu',[],'Fuse',[]), 1, Nsim );
            % Print progress bar:
            fprintf('|%s|\n',repmat('-',1,Nsim));
            fprintf('|');
            for ii = 1:Nsim
                fprintf('+');
                this.updatePose;
                err_R = this.syntheticOrientation;
                for k = 1:Nfields
                    f = fields{k};
                    err(ii).(f) = err_R.(f);
                end
            end
            fprintf('|\n');
            all_err = [ [err.P3oA]
                        [err.Elqu]
                        [err.Fuse] ]';
            % Plot results statistics
            boxplot( all_err );
        end
        
        function plotSeveralCubeResults( ~,...
                  err_elqursh, global_err_elqursh,...
                  err_P3oA, global_err_P3oA, global_err_P3oA_W )
            
            % Colors configuration
            c_blue = [51 51 255]/255;
            c_oran = [255 128 0]/255;
            c_gree = [102 255 102]/255;
            colors = {c_blue, c_oran, c_gree};
              
            % Plot results
            h_ = figure;
            fm = 1; fn = 2;
            title('Error histogram'); hold on;
            
%             subplot(fm,fn,1); hold on;
%             plot(1, err_elqursh, '*b');
%             plot(2, err_P3oA, '*g');
%             ax = axis; axis([0 3 ax(3:4)]);
            
            subplot(fm,fn,1); hold on;
            err = NaN( max(numel(err_elqursh),numel(err_P3oA)), 2 );
            err(1:numel(err_elqursh),1) = err_elqursh;
            err(1:numel(err_P3oA),2) = err_P3oA;
%             xbinscenters = [0:0.1:1, 2:10];
%             hist( err, xbinscenters );
            edges = logspace(-2,2,10);
            N = histc( err, edges );
            % Normalize each method values scaling wrt total number of
            % elements
            N = N * diag( [1/numel(err_elqursh), 1/numel(err_P3oA)] );
            % Plot bars figure
            bar(edges,N,'histc');
            set(gca, 'Xscale', 'log')
            h = findobj(gca,'Type','patch');
            set(h(2),'FaceColor',c_blue,'EdgeColor','w'); % Elqursh
            set(h(1),'FaceColor',c_oran,'EdgeColor','w'); % P3oA
            legend('Elqursh','P3oA','Location','NorthEast')
            
            subplot(fm,fn,2); hold on;
            xbinscenters = 0:0.1:1;
            hist( [global_err_elqursh
                   global_err_P3oA
                   global_err_P3oA_W]', xbinscenters );
            h = findobj(gca,'Type','patch');
            set(h(3),'FaceColor',c_blue,'EdgeColor','w'); % Elqursh
            set(h(2),'FaceColor',c_oran,'EdgeColor','w'); % P3oA
            set(h(1),'FaceColor',c_gree,'EdgeColor','w'); % W-P3oA
            legend('Elqursh','P3oA','W-P3oA','Location','NorthEast')
            
            set(h_,'units','normalized','outerposition',[0 0 1 1]);
        end
        
        function testDistance( this, arr_d, Nsim )
            N_methods = 3;
            
            Nd = numel(arr_d);
            err1 = cell(1,Nd);
            err2 = cell(1,Nd);
            gerr1 = cell(1,Nd);
            gerr2 = cell(1,Nd);
            gerr3 = cell(1,Nd);
            
            for ii=1:Nd
                d = arr_d(ii);
                this.poseFactory.min_d = d;
                this.poseFactory.max_d = d;
                [err1{ii}, gerr1{ii}, err2{ii}, gerr2{ii}, gerr3{ii}] = ...
                    this.compareSeveralCubeResults( Nsim );
                
                Cval{ii} = num2str(d);
            end
            
            % Store simulation data
            file = datestr(now);
            file = strrep( file,'-','_' );
            file = strrep( file,' ','_' );
            file = strrep( file,':','_' );
            file = ['testDistance_',file,'.mat'];
            file = fullfile(pwd,'Odometry','store',file);
            save( file, 'err1','gerr1', 'err2','gerr2', 'gerr3',...
                'arr_d', 'Nsim' );
            aux_struct = struct( this ); %#ok<NASGU>
            save( file, '-struct', 'aux_struct',...
                    'cam_sd', 'cube_sd', 'Cam', 'Cube', '-append' );
            
            % Matrix of stacked data
%             M = [ cell2mat( gerr1' )', cell2mat( gerr2' )' ];
            M = [ cell2mat( gerr1' )', cell2mat( gerr2' )', ...
                  cell2mat( gerr3' )' ];
            
            Nx = Nd;
            % Cval contains the string with X-value
            % for each column of data
            Cval = repmat( Cval, 1, N_methods );
            % Ctag contains the string with method corresponding
            % to each column of data
%             Ctag = [ repmat({'Elqursh'},1,Nx),...
%                      repmat({'P3oA'},1,Nx) ];
            Ctag = [ repmat({'Elqursh'},1,Nx),...
                     repmat({'P3oA'},1,Nx),...
                     repmat({'P3oA-W'},1,Nx)];
            
            % Parameters to control the position in X label
            Npos    = 5;    % gap between samples in X label
            pos_ini = 1;    % initial value in X label
            Nsep    = 0.5;  % gap between methods in X label
            % Load the vector of positions
            pos_aux = pos_ini:Npos:Npos*Nx;
            pos_    = pos_aux;
            pos_1   = [];
            for i = 1:N_methods-1
                pos_ = [pos_ pos_aux+i*Nsep];
            end
            
            color_ = [0.2980392156862745 0.4470588235294118 0.6901960784313725;
                0.3333333333333333 0.6588235294117647 0.40784313725490196;
%                 0.7686274509803922 0.3058823529411765 0.3215686274509804;
                %0.5058823529411764 0.4470588235294118 0.6980392156862745;];
                0.8                0.7254901960784313 0.4549019607843137];
            color = repmat(color_,Nx,1);
            
            h = figure; hold on;
            boxplot(M,{Cval,Ctag},...
                'position',sort(pos_),'colors', color,...
                'factorgap',0,'whisker',0,'plotstyle','compact');
            
            % Remove the outliers
            bp_ = findobj(h, 'tag', 'Outliers'); % Find handler
            set(bp_,'Visible','Off'); % Remove object
            
            % Plot lines
            median_ = median(M);
            for i = 1:N_methods
                x_ = pos_(1, Nx*(i-1)+1:Nx*i);
                y_ = median_(1, Nx*(i-1)+1:Nx*i);
                plot(x_,y_,'Color',color(i,:),'LineWidth',1.5);
            end
            
            % Plot legend
            Cleg = {'Elqursh','O3PA','O3PA-W'};
            Clab = {Cval{1,1:Nx}};
%             set(gca,'YScale','log');
            set(gca,'XTickLabel',{' '});
            [legh,objh,outh,outm] = legend(Cleg);
            set(objh,'linewidth',3);
            set(gca,'XTick',pos_aux);
            set(gca,'XTickLabel',Clab);
        end
        
        function [err_R,ERR_R,err_t,ERR_t,poses] =...
                freiburgOdometry( this, dataset_folder, dataset_type,...
                                  i0, for_step, debug )
            if ~exist('i0','var')
                i0 = [1];
            end
            if numel(i0)==1
                i0 = [i0 +inf];
            end
            
            if ~exist('for_step','var')
                for_step = double(1);
            end
            
            if ~exist('debug','var')
                debug = false;
            end
            
            bad_i_frames = [350:354,...
                            357:358,...
                            374:376]; % From visual inspection
            
%             raw = CRawlogCam( dataset_folder, [], 'Freiburg' );
            raw = CRawlogCam( dataset_folder, [], dataset_type );
            
            % Get camera configuration
%             config_file = fullfile( pwd, 'configs', 'freiburg3RGB.ini' );
            config_file = fullfile( pwd, 'configs', [raw.typeOfSource,'.ini'] );
            SConfigCam = readConfigFile( config_file );
            this.Cam = CRealCamera( SConfigCam );

            tracker1 = CGtracker([],false);
            tracker2 = CGtracker([],false);
%             tracker  = CGtracker; % Make independent object
            tracker = tracker2; % Copy handle (copy of pointer)
            tracker.WITH_DEB = debug;
            
            % Set GT triplets (for P3oA method) (by visual inspection)
            switch raw.typeOfSource
                case 'Freiburg'
                % Freiburg
                idxs_GT = {[1 4 8 10]
                           [2 5 7 12]
                           [3 6 9 11]};
                case 'Blender'
                    % Blender
                    idxs_GT = {[1 4 7]
                               [2 5 8]
                               [3 6 9]};
                    % Get 3D GT segments
                    cube_GT = CHalfCube( 2, eye(3), ones(3,1) );
                    segs3D_GT = [cube_GT.segments{:}];
                    CGT.segs3D( segs3D_GT );
%                     figure; hold on;
%                     segs3D_GT.plot3('-k',{'1','2','3','4','5','6','7','8','9'});
%                     axis equal
                    % Conversion map

            end
            triplets_GT = allcomb( idxs_GT{:} )';
            % Use fixed ordering: ascend order (since x-y-z id does not matter)
            triplets_GT = sort(triplets_GT,1,'ascend'); %#ok<UDIM>
            % Order columns
            triplets_GT = sortrows(triplets_GT')';
            % DEBUG: Store persistent value
            CGT.triplets(triplets_GT);
            
            % Set GT pairs (for translation method) (by visual inspection)
            switch raw.typeOfSource
                case 'Freiburg'
                % Freiburg
                pairs_GT = [ nchoosek([1 4 8 10],2) % X vanishing points
                             nchoosek([2 5 7 12],2) % Y vanishing points
                             nchoosek([3 6 9 11],2) % Z vanishing points
                             nchoosek([7 8 9], 2) % +++ point
                             nchoosek([2 3 8], 2) % -++ point
                             nchoosek([1 2 11], 2) % --+ point
                             nchoosek([10 11 12], 2) % --- point
                             nchoosek([3 4 12], 2) % -+- point
                             nchoosek([4 5 9], 2) % ++- point
                             nchoosek([5 6 10], 2) % +-- point
                             nchoosek([1 6 7], 2) ]'; % +-+ point
            end
            % Use fixed ordering: ascend order (since x-y-z id does not matter)
            pairs_GT = sort(pairs_GT,1,'ascend'); %#ok<UDIM>
            % Order columns
            pairs_GT = sortrows(pairs_GT')';
            % DEBUG: Store persistent value
            CGT.pairs(pairs_GT);
            
            % Treat err as a struct
            err_R = repmat( struct('P3oA',[],'Elqu',[],'Fuse',[]), 1, raw.Nobs-1 );
            ERR_R = repmat( struct('P3oA',[],'Elqu',[],'Fuse',[]), 1, raw.Nobs-1 );
            err_t = repmat( struct('P3oA',[],'Elqu',[],'Fuse',[]), 1, raw.Nobs-1 );
            ERR_t = repmat( struct('P3oA',[],'Elqu',[],'Fuse',[]), 1, raw.Nobs-1 );
            R_W_P3oA = raw.frames(i0(1)).pose.R;
            R_W_Elqu = raw.frames(i0(1)).pose.R;
            R_W_Fuse = raw.frames(i0(1)).pose.R;
            R_W_gt   = raw.frames(i0(1)).pose.R;
            t_W_P3oA = raw.frames(i0(1)).pose.t;
            t_W_Elqu = raw.frames(i0(1)).pose.t;
            t_W_Fuse = raw.frames(i0(1)).pose.t;
            t_W_gt   = raw.frames(i0(1)).pose.t;
            missing  = 0; % Counter of missed steps or frames
            history.missed = [];
            
            % Store poses too
            poses = repmat( struct('gt',[],'P3oA',[],'Elqu',[],'Fuse',[]), 1, raw.Nobs );
            % Store first pose as GT
            poses(1).gt   = raw.frames(i0(1)).pose;
            poses(1).P3oA = raw.frames(i0(1)).pose;
            poses(1).Elqu = raw.frames(i0(1)).pose;
            poses(1).Fuse = raw.frames(i0(1)).pose;

            
%             for_step = 10; % Is an input argument now
            for i=i0(1):for_step:raw.Nobs-for_step % Step size 1
                if i>=i0(2)
                    break;
                end
                try
                    if missing == 0
                        % Usual case, everything is OK
                        % Get as first index the i-th frame
                        i1 = i;
                    else % missing > 0
                        % Case some frame has been missed (because of bad
                        % quality, etc.)
                        i1 = i-missing*for_step; % Go back as many frames as missed steps
                        if missing > 10
                            % Something must have gone wrong
                            warning('%d missing frames reached, check',missing);
                            keyboard
                        end
                    end
%                     i2 = i+1; % Second frame is always taken (i+1)-th (wrt current step)
                    i2 = i+for_step; % Second frame is always taken (i+1)-th (wrt current step)
%                     i2 = i+20; % Second frame is always taken (i+1)-th (wrt current step)
                if ~exist( raw.frames(i2).path_metafile, 'file' )
                    warning('Not processed lines in frame %d',i2);
                    break
                end
                % Load segments for current step
                tracker1.loadSegs( raw.frames(i1).path_metafile );
                tracker2.loadSegs( raw.frames(i2).path_metafile );

                % Plot frame
                im = raw.frames(i2).loadImg;
                tracker.loadImage( im );
                if ~exist('hIm','var')
                    figure('Name','Track figure');
                    hIm = imshow( tracker.img ); hold on;
                    freezeColors;
%                     set(gcf,'Position',...)
                else
                    set(hIm,'CData',tracker.img);
                end
                tags  = tracker.segs.tags( tracker.maskSegs );
                if exist('hSegs','var')
                    delete(hSegs);
                    delete(gSegs);
                end
                [hSegs, gSegs] = tracker.segs.segs(tracker.maskSegs).plot('r', tags);
                % Change tags color for better visualization
                set(gSegs,'Color','r');
               
                % Tag segments
                % Extract segments arrays (to avoid accessing problems)
                segs{1} = tracker1.segs.segs;
                segs{2} = tracker2.segs.segs;
                if isempty([tracker.segs.segs.tag])
                    % If segments are not tagged, add tag according to index
                    for k=1:2
                        num_tags = num2cell(1:numel(segs{k}));
                        [segs{k}.tag] = deal( num_tags{:} );
                    end
                    % Remove masked values (non valid)
                    % NOTE: Keep for id
%                     segs{1}(~tracker1.maskSegs)=[];
%                     segs{2}(~tracker2.maskSegs)=[];
                end
                % Note: containers.Map could be used for segments with tag key                
                % Find common tags (match)
                [common_tags, I1, I2] = intersect( ...
                    [segs{1}(tracker1.maskSegs).tag],...
                    [segs{2}(tracker2.maskSegs).tag] ); %#ok<ASGLU>
                % Create matches array: 2xM matrix where each column
                % [idx1;idx2] gives the indexes of segments in arrays
                % segs{1} and segs{2} that form a potential match pair
%                 matches = [I1, I2]'; % For general cases
                matches = repmat( common_tags, 2,1 ); % For already matched case
                                                  
                % Get GT relative pose from Freiburg
                R_gt = raw.frames(i1).pose.R' * raw.frames(i2).pose.R;
                CGT.R(R_gt); % Store persistent GT value
                % trel trans is taken (^c1)t(_c2), so since GT is given as
                % (^w)t(_ck) the formula below is equivalent to
                % (^c1)[(^c1)t(_c2)] = (^c1)R(_w) * ( (^w)t(_c2) - (^w)t(_c1) )
                if exist('t_gt','var')
                    % Compute GT value for scale between previous pair of
                    % frames translation vector and current pair of frames one
                    s_gt = norm( raw.frames(i1).pose.R' * ( raw.frames(i2).pose.t - raw.frames(i1).pose.t ) ) / t_gt_norm;
                end
                t_gt = raw.frames(i1).pose.R' * ( raw.frames(i2).pose.t - raw.frames(i1).pose.t );
                t_gt_norm = norm( t_gt ); % The distance between centers
                t_gt = snormalize( t_gt ); % For scale indeterminacy
                CGT.t(t_gt); % Store persistent GT value
                
                % Get GT 2D segments (if 3D GT exists, e.g. for Blender)
                if exist('segs3D_GT','var')
                    Cam1 = this.Cam.cloneAsSimCam(0);
                    Cam2 = this.Cam.cloneAsSimCam(0);
                    Cam1.R = raw.frames(i1).pose.R;
                    Cam1.t = raw.frames(i1).pose.t;
                    Cam2.R = raw.frames(i2).pose.R;
                    Cam2.t = raw.frames(i2).pose.t;
                    CGT.any('segs1', segs3D_GT.project(Cam1));
                    CGT.any('segs2', segs3D_GT.project(Cam2));
%                     sgt1 = segs3D_GT.project(Cam1);
%                     s1 = segs{1};
%                     figure, hold on; sgt1.plot('-k',true); s1.plot('-b',true);
                end
                
                %% Compute relative values
                % Testing with Elqursh code
                tracker1.loadImage( raw.frames(i1).loadImg ); % Debug
                tracker2.loadImage( raw.frames(i2).loadImg ); % Debug
                [R_Elqu, V_Elqu, t_Elqu, triplets] = this.codeElqursh( segs{1}, segs{2}, matches',...
                                  this.Cam.size, tracker1, tracker2 );
                R_Elqu = R_Elqu'; % Transpose because according to Elqursh notation R = (^c2)R(_c1)
                t_Elqu = - R_Elqu * t_Elqu; % Change criterion
                if this.WITH_DEBUG
                    % Check inliers
                    % TODO: Build set of Elqursh inliers
%                     missed_inliers = setdiff( CGT.triplets', triplets','rows')'; % Missed inliers
%                     taken_outliers = setdiff( triplets', CGT.triplets','rows')'; % Taken outliers
                end
                              
                % Testing with P3oA code
                % Rotation threshold depends a lot on dataset error (higher
                % in reality than Blender)
                switch raw.typeOfSource
                    case 'Freiburg'
                        rotThres = 3;
%                         rotThres = 5;
                        % Hard code thresholds for frames
                        if i==111
                            rotThres = 5;
                        end
                        if i==131
                            rotThres = 1;
                        end
                    case 'Blender'
                        rotThres = 0.5;
                end
                % DEBUG:
                if exist('cube_GT','var')
                    CGT.any('Cam1',Cam1);
                    CGT.any('Cam2',Cam2);
                    CGT.any('Cube',cube_GT);
                end
                [R_P3oA, V_P3oA, triplets] = this.codeP3oA( segs{1}, segs{2}, matches, this.Cam.K, rotThres );
                if this.WITH_DEBUG
                    % Check inliers
                    % TODO: Build set of Elqursh inliers
                    missed_inliers = setdiff( CGT.triplets', triplets','rows')'; % Missed inliers
                    taken_outliers = setdiff( triplets', CGT.triplets','rows')'; % Taken outliers
                end
                fprintf('Compare GT and estimate rotation [deg]: %f\n',angularDistance(CGT.R,R_P3oA) );
%                 tranThres = 0.1; % IMPORTANT: Experiment with this threshold
%                 tranThres = 0.2;
%                 tranThres = 2;
%                 tranThres = 4;
%                 tranThres = 5; % Use high threshold if outliers are filtered
                tranThres = 7; % Use high threshold if outliers are filtered
                if i==11
                    tranThres = 2;
                end
                [t_P3oA, pairs, im_points] = this.codeTranslation( segs{1}, segs{2}, matches, R_P3oA, this.Cam.K, tranThres );
                % DEBUG:
                fprintf('Compare GT and estimate translation [deg]: %f\n',acosd( t_gt'*t_P3oA ) );
                disp([t_gt,t_P3oA]);
                if exist('im_points_prev','var')
                    [ common_pairs, idxs_pairs_1, idxs_pairs_2 ] = ...
                        intersect( pairs_prev{1}', pairs{1}', 'rows' );
                    common_pairs = common_pairs';
                    % Prepare compatible points
                    recon_points = { im_points_prev{1}(:,idxs_pairs_1);
                                     im_points{1}(:,idxs_pairs_2);
                                     im_points{2}(:,idxs_pairs_2) };
                    [s,pts3D] = this.codeReconstruction( recon_points,...
                            { R_P3oA_prev, R_P3oA }, { t_P3oA_prev, t_P3oA },...
                            this.Cam.K, this.Cam.size );
                end
                if exist('s','var')
                    t_P3oA_norm = t_P3oA_norm_prev * s;
%                     t_P3oA_norm = t_P3oA_norm_prev * s_gt;
                else
                    % First use GT
%                     t_P3oA_norm = t_gt_norm * 0.7199; % Taken from last frame relation between absolute translation norms
                    t_P3oA_norm = t_gt_norm;
                end
                pairs_prev = pairs;
                im_points_prev = im_points;
                R_P3oA_prev = R_P3oA;
                t_P3oA_prev = t_P3oA;
                t_P3oA_norm_prev = t_P3oA_norm;

                % Fuse data from both methods
                V1 = [V_P3oA{1}, V_Elqu{1}];
                V2 = [V_P3oA{2}, V_Elqu{2}];
                % Test for outliers in fused set
                d = acosd( dot( V1, R_P3oA*V2, 1) );
%                 d = asind( sqrt( sum( (V1 - R_P3oA*V2).^2, 1 ) ) );
%                 inliers = find( d < rotThres );
                inliers = d < rotThres;
                if this.WITH_DEBUG
                    fprintf('Inliers for Fused: %d/%d\n',sum(inliers),size(V1,2));
                end
                % Keep only inliers
                V1 = V1(:,inliers);
                V2 = V2(:,inliers);
                
                [Ur,~,Vr] = svd(V1*V2');
                if (det(Ur)*det(Vr)>=0), Sr = eye(3);
                else Sr = diag([1 1 -1]);
                end
                R_Fuse = Ur*Sr*Vr';
                [t_Fuse, pairs] = this.codeTranslation( segs{1}, segs{2}, matches, R_Fuse, this.Cam.K, tranThres );
                
                %% Compute absolute (cumulative) values (relative to World)
                % Store previous values (for corrections)
                previous.R_W_P3oA = R_W_P3oA;
                previous.R_W_Elqu = R_W_Elqu;
                previous.R_W_Fuse = R_W_Fuse;
                previous.t_W_P3oA = t_W_P3oA;
                previous.t_W_Elqu = t_W_Elqu;
                previous.t_W_Fuse = t_W_Fuse;
                
                % Cumulative absolute rotation (^w)R(_c2)
                R_W_P3oA = R_W_P3oA * R_P3oA;
                R_W_Elqu = R_W_Elqu * R_Elqu;
                R_W_Fuse = R_W_Fuse * R_Fuse;
                
                % Cumulative absolute translation (^w)R(_c2)
                % TODO: What to do with unknown scale?
                % TEMPORAL: translation norm corrected with GT value
%                 t_W_P3oA = t_W_P3oA + R_W_P3oA * t_P3oA * t_gt_norm;
%                 t_W_Elqu = t_W_Elqu + R_W_Elqu * t_Elqu * t_gt_norm;
%                 t_W_Fuse = t_W_Fuse + R_W_Fuse * t_Fuse * t_gt_norm;
                t_W_P3oA = t_W_P3oA + R_W_P3oA * t_P3oA * t_P3oA_norm;
                t_W_Elqu = t_W_Elqu + R_W_Elqu * t_Elqu * t_P3oA_norm; % TODO: Own
                t_W_Fuse = t_W_Fuse + R_W_Fuse * t_Fuse * t_P3oA_norm; % TODO: Own
                
                % Store estimated poses:
                poses(i2).gt   = CPose3D( raw.frames(i2).pose.R, raw.frames(i2).pose.t );
                poses(i2).P3oA = CPose3D( R_W_P3oA, t_W_P3oA );
                poses(i2).Elqu = CPose3D( R_W_Elqu, t_W_Elqu );
%                 poses(i2).Fuse = CPose3D( R_W_Fuse, t_W_Fuse ); %
%                 TEMPORALLY deactivated
                
                
                %% Compute errors
                % Get second frame absolute GT pose
                R_W_gt = raw.frames(i2).pose.R;
                t_W_gt = raw.frames(i2).pose.t;
                
                % Relative errors
                % - Rotation
                err_R(i).P3oA = angularDistance(R_P3oA,R_gt);
                err_R(i).Elqu = angularDistance(R_Elqu,R_gt);
                err_R(i).Fuse = angularDistance(R_Fuse,R_gt);
                % - Translation
                % Scaled with translation norm
%                 err_t(i).P3oA = norm(t_P3oA - t_gt) * t_gt_norm;
%                 err_t(i).Elqu = norm(t_Elqu - t_gt) * t_gt_norm;
%                 err_t(i).Fuse = norm(t_Fuse - t_gt) * t_gt_norm;
                err_t(i).P3oA = acosd( t_gt' * t_P3oA );
                err_t(i).Elqu = acosd( t_gt' * t_Elqu );
                err_t(i).Fuse = acosd( t_gt' * t_Fuse );

                % Absolute errors
                % - Rotation
                ERR_R(i).P3oA = angularDistance(R_W_P3oA, R_W_gt);
                ERR_R(i).Elqu = angularDistance(R_W_Elqu, R_W_gt);
                ERR_R(i).Fuse = angularDistance(R_W_Fuse, R_W_gt);
                
                % - Translation
                ERR_t(i).P3oA = norm(t_W_P3oA - t_W_gt);
                ERR_t(i).Elqu = norm(t_W_Elqu - t_W_gt);
                ERR_t(i).Fuse = norm(t_W_Fuse - t_W_gt);
                
                % Print (display) values
                fprintf('\n');
                fprintf('--------\n');
                fprintf('Rotation - GT angle: %f\n', angularDistance(R_gt,eye(3)));
                fprintf('--------\n');
                fprintf('%d: Relative error [deg]\t\t\t%d: Absolute error [deg]\n',i,i);
                fprintf('P3oA    -> %f\t\t\tP3oA    -> %f\n', err_R(i).P3oA, ERR_R(i).P3oA);
                fprintf('Elqursh -> %f\t\t\tElqursh -> %f\n', err_R(i).Elqu, ERR_R(i).Elqu);
                fprintf('Fuse    -> %f\t\t\tFuse    -> %f\n', err_R(i).Fuse, ERR_R(i).Fuse);
                fprintf('P3oA rotation missed inliers:\n');
                disp( CGT.missedInliers( triplets ) );
                fprintf('P3oA rotation slipped outliers:\n');
                disp( CGT.slippedOutliers( triplets ) );
                
                fprintf('-----------\n');
                fprintf('Translation - GT norm: %f\n', t_gt_norm);
                fprintf('-----------\n');
                fprintf('%d: Relative error [deg]\t\t\t%d: Absolute error [m]\n',i,i);
                fprintf('P3oA    -> %f\t\t\tP3oA    -> %f\n', err_t(i).P3oA, ERR_t(i).P3oA);
                fprintf('Elqursh -> %f\t\t\tElqursh -> %f\n', err_t(i).Elqu, ERR_t(i).Elqu);
                fprintf('Fuse    -> %f\t\t\tFuse    -> %f\n', err_t(i).Fuse, ERR_t(i).Fuse);
                fprintf('P3oA translation missed inliers:\n');
                disp( CGT.missedInliersT( pairs{1} ) );
                fprintf('P3oA translation slipped outliers:\n');
                disp( CGT.slippedOutliersT( pairs{1} ) );

                if exist('s','var')
                    fprintf('-----------\n');
                    fprintf('Scale - GT: %f\n', s_gt);
                    fprintf('-----------\n');
                    fprintf('%d: Computed scale [ ]\n',i);
                    fprintf('P3oA    -> %f\n', s);
                end
                
                % Plot inliers
%                 for k = find(mask_thres)
%                     h = tracker.segs(triplets(:,k)).plot(...
%                         {'y','LineWidth',2});
%                     delete(h);
%                 end

                    
%                 keyboard
                pause(0.01)
                
                % Check errors (inspect if some is too big)
                test_bad_frame = [ %err_R(i).P3oA > 0.9 % Usually very bad values occur with blurred images
                                    err_R(i).P3oA > 2
%                                    err_R(i).Elqu > 0.9
%                                    err_t(i).P3oA > 0.05 % Avoid big steps errors in translation
                                   any( i2 == bad_i_frames ) ]; % We control that blurred images are not included from bad_i_frames to avoid problems with GT, etc.
                if any( test_bad_frame )
                    switch find( test_bad_frame, 1 )
                        case 1
                            warning('Check frames #%d and #%d, error in P3oA is %f\n',i1,i2,err_R(i).P3oA);
                        case 2
                            warning('Check frames iteration #%d, error for translation is %f\n',i,err_t(i).P3oA);
                        case 3
                            warning('Frame #%d is marked bad frame\n',i2);
                    end
                    
                    
                    % Substitute values of current iteration with NaN
                    C = cell(3,1);
                    [C{:}] = deal( NaN );
                    err_R(i) = cell2struct(C,{'P3oA','Elqu','Fuse'});
                    ERR_R(i) = cell2struct(C,{'P3oA','Elqu','Fuse'});
                    err_t(i) = cell2struct(C,{'P3oA','Elqu','Fuse'});
                    ERR_t(i) = cell2struct(C,{'P3oA','Elqu','Fuse'});
                    
                    % Undo the absolute pose elements computation
                    % Use values stored in 'previous' struct fields
                    fields = fieldnames( previous );
                    for field = fields(:)' % Construct row cell array of elements
                        assert( numel(field) == 1 );
                        field = field{1}; %#ok<FXSET>
                        eval( [field,'= previous.(field);'] );
                    end
                    % Remove bad values from stored poses:
                    poses(i2).gt   = [];
                    poses(i2).P3oA = [];
                    poses(i2).Elqu = [];
                    poses(i2).Fuse = [];
                    
% % %                     % Undo the absolute rotation computation
% % %                     % TODO: Use different variables to get this simpler?
% % %                     R_W_P3oA = R_W_P3oA * R_P3oA';
% % %                     R_W_Elqu = R_W_Elqu * R_Elqu';
% % %                     R_W_Fuse = R_W_Fuse * R_Fuse';
% % %                     % TODO: Undo translation too (better with different variables)

                    missing = missing + 1; % Counter of missed frames because of bad quality
                    history.missed(end+1) = i2; % Save index of missed image                    
                else
                    % Arrived to this point, everything went OK (no missed frame)
                    missing = 0;
                end

                catch exception
                    disp(exception.message);
                    for kstack=1:numel(exception.stack)
                        disp(exception.stack(kstack));
                    end
                    keyboard
                end
            end
            fprintf('Finished odometry from frames #%d to #%d\n',i0(1),i);
            
            % Plot statistics
%             m = 3; n = 6;
            m = 2; n = 12;
            figure('Name','Error of results'); hold on;
            % First row
%             M_R = [ [err_R.P3oA]
%                     [err_R.Elqu] ]';
%                     [err_R.Fuse] ]';
            subplot(m,n,[1 2 3]); hold on;
%             boxplot(M_R);
            plot( [err_R.P3oA], 'r-' ); plot( [err_R.P3oA], 'r.' );
            plot( [err_R.Elqu], 'g-' ); plot( [err_R.Elqu], 'g.' );
%             plot( [err_R.Fuse], 'b-' ); plot( [err_R.Fuse], 'b.' );
            subplot(m,n,[4 5 6]); hold on;
            plot( [ERR_R.P3oA], 'r-' ); plot( [ERR_R.P3oA], 'r.' );
            plot( [ERR_R.Elqu], 'g-' ); plot( [ERR_R.Elqu], 'g.' );
%             plot( [ERR_R.Fuse], 'b-' ); plot( [ERR_R.Fuse], 'b.' );
            % Second row
%             M_t = [ [err_t.P3oA]
%                     [err_t.Elqu]
%                     [err_t.Fuse] ]';
            subplot(m,n,[7 8 9]); hold on;
%             boxplot(M_t);
            plot( [err_t.P3oA], 'r-' ); plot( [err_t.P3oA], 'r.' );
            plot( [err_t.Elqu], 'g-' ); plot( [err_t.Elqu], 'g.' );
            subplot(m,n,[10 11 12]); hold on;
            plot( [ERR_t.P3oA], 'r-' ); plot( [ERR_t.P3oA], 'r.' );
            plot( [ERR_t.Elqu], 'g-' ); plot( [ERR_t.Elqu], 'g.' );
%             plot( [ERR_t.Fuse], 'b-' ); plot( [ERR_t.Fuse], 'b.' );
            % Third row
            subplot(m,n,6+(7:8)); hold on;
            hist( [err_R.P3oA] );
            subplot(m,n,6+(9:10)); hold on;
            hist( [err_R.Elqu] );
%             subplot(m,n,6+(11:12)); hold on;
%             hist( [err_R.Fuse] );
            
            save('history.mat','-struct','history');
            keyboard
        end
        
        function odoFreiburg( this, dataset_folder, debug )
            if ~exist('debug','var')
                debug = false;
            end
            
            % Get camera configuration
            config_file = fullfile( pwd, 'configs', 'freiburg3RGB.ini' );
            SConfigCam = readConfigFile( config_file );
            this.Cam = CRealCamera( SConfigCam );
            
            raw = CRawlogCam( dataset_folder, [], 'Freiburg' );
            
            if 1              
                % See tracking of real camera
                simCam = CSimCamera( eye(3), zeros(3,1),...
                    this.Cam.K, this.Cam.res, this.Cam.f, this.Cam.sd );
                figure('Name','GT tracking');, hold on;
                axis([-2 2 -2 2 0 3]);
                % Create simulated cube
                cube = CCube( 1 );
                cube.plot3;
                for i=1:raw.Nobs
                    simCam.R = raw.frames(i).pose.R;
                    simCam.t = raw.frames(i).pose.t;
                    h = simCam.plot3_CameraFrustum;
                    pause(0.01)
                    delete(h);
                end
            end
            
            tracker  = CGtracker;
            tracker1 = CGtracker([],false);
            tracker2 = CGtracker([],false);
            tracker.WITH_DEB = debug;
            
            ERR_ = zeros(1,raw.Nobs-1);
            err_ = zeros(1,raw.Nobs-1);
            err_Elqursh = zeros(1,raw.Nobs-1);
            R_cum = raw.frames(1).pose.R;
            for i=1:raw.Nobs-1
                try
                if ~exist( raw.frames(i).path_metafile, 'file' )
                    break
                end
%                 tracker.loadSegs( raw.frames(i).path_metafile );
%                 tracker1.loadSegs( raw.frames(i).path_metafile );
                i1 = i;
                i2 = i+1;
                tracker.loadSegs( raw.frames(i2).path_metafile );                
                tracker1.loadSegs( raw.frames(i1).path_metafile );
                tracker2.loadSegs( raw.frames(i2).path_metafile );
                
                % Plot frame
                im = raw.frames(i2).loadImg;
                tracker.loadImage( im );
                
                cla
                imshow( tracker.img ); hold on;
                freezeColors;
                tags = tracker.segs.tags( tracker.maskSegs );
%                 tags = cellfun(@(x)num2str(x), num2cell(1:numel(tracker.segs)),...
%                     'UniformOutput', false);
                tracker.segs.segs(tracker.maskSegs).plot('r', tags);
                
                set(gcf,'Position',[482   284   808   570]);
                pause(0.5);
                
                % Get all possible segment triplets
                % Test the number of segs is the same
                if numel(tracker1.maskSegs) ~= numel(tracker2.maskSegs)
                    warning('Different number of segments, matching could be wrong');
                    keyboard
                    n_ = max( [ numel(tracker1.maskSegs) numel(tracker2.maskSegs) ] );
                    temp1_ = tracker1.maskSegs;
                    temp2_ = tracker2.maskSegs;
                    tracker1.maskSegs = false(1,n_);
                    tracker2.maskSegs = false(1,n_);
                    tracker1.maskSegs( find(temp1_) ) = true;
                    tracker2.maskSegs( find(temp2_) ) = true;
                end
                pairs = find( tracker1.maskSegs & tracker2.maskSegs );
                
                % Testing with Elqursh code
                tracker1.loadImage( raw.frames(i1).loadImg );
                tracker2.loadImage( raw.frames(i2).loadImg );
                R_Elqursh = this.codeElqursh( tracker1.segs.segs, tracker2.segs.segs, pairs,...
                                  size(tracker.img), tracker1, tracker2 );
                              
                % Testing with P3oA code
                R_P3oA = this.codeP3oA( tracker1.segs.segs, tracker2.segs.segs, this.Cam.K );
                
%                 triplets = nchoosek(1:numel(tracker1.segs),3)';
%                 Ntriplets = nchoosek(numel(tracker1.segs),3);
                triplets = nchoosek(pairs,3)';
                Ntriplets = nchoosek(numel(pairs),3);
                
                CNbp_1 = cell(1,Ntriplets);
                CNbp_2 = cell(1,Ntriplets);
                mask_remove = false(1,Ntriplets);
                for k=1:Ntriplets
                    % Extract and calibrate homogeneous lines
%                     l_ = [tracker.segs( triplets(:,k) ).l];
%                     Nbp_ = snormalize( this.Cam.K' * l_ );

                    segs1 = tracker1.segs( triplets(:,k) ); 
                    l_1 = [segs1.l];
%                     l_1 = [tracker1.segs( triplets(:,k) ).l];
                    Nbp_1 = snormalize( this.Cam.K' * l_1 );
                    
                    segs2 = tracker2.segs( triplets(:,k) ); 
                    l_2 = [segs2.l];
%                     l_2 = [tracker2.segs( triplets(:,k) ).l];
                    Nbp_2 = snormalize( this.Cam.K' * l_2 );
                    
                    % Check non-meeting set feasibility and
                    % rule out bad configurations
                    sign_1 = CTrihedronSolver.signature(Nbp_1);
                    sign_2 = CTrihedronSolver.signature(Nbp_2);
                    if 0
                        fprintf('Triplet %d-%d-%d has signature %d\n',...
                            triplets(1,k), triplets(2,k), triplets(3,k),...
                            sign_1);
                    end
                    if ( sign_1 > 0 || sign_2 > 0 )
                        mask_remove( k ) = true;
                    else
                        CNbp_1{k} = Nbp_1;
                        CNbp_2{k} = Nbp_2;
                    end
                end
                % Remove bad triplets
                triplets(:,mask_remove) = [];
                CNbp_1(mask_remove) = [];
                CNbp_2(mask_remove) = [];
                    
                % Rests checking min angles constraint (sum > 180?)
                
                % Solve feasible triplets
                Ntriplets = size(triplets,2);
                V_1 = cell(2,Ntriplets);
                V_2 = cell(2,Ntriplets);
                a0_1 = zeros(2,Ntriplets);
                a0_2 = zeros(2,Ntriplets);
                CR  = cell(4,Ntriplets);
                for k=1:Ntriplets
                    trihedronSolver_1 = CTrihedronSolver( CNbp_1{k}, this.Cam.K );
                    trihedronSolver_2 = CTrihedronSolver( CNbp_2{k}, this.Cam.K );
                    % Configure solver to get both solutions (with any sign
                    % for vanishing direction)
                    trihedronSolver_1.WITH_SIGNED_DIRECTIONS = false;
                    trihedronSolver_1.WITH_SIGNED_DETERMINANT = false;
                    trihedronSolver_2.WITH_SIGNED_DIRECTIONS = false;
                    trihedronSolver_2.WITH_SIGNED_DETERMINANT = false;
                    
                    % trihedronSolver.loadSegments( tracker.segs( triplets(:,k) ) );
                    V_1(:,k) = trihedronSolver_1.solve;
                    a0_1(:,k) = trihedronSolver_1.a0;
                    V_2(:,k) = trihedronSolver_2.solve;
                    a0_2(:,k) = trihedronSolver_2.a0;
                end
                
                CR = cell(2,2);
                for k=1:Ntriplets
                    % Compute 4 possible rotations
                    % Should check Frobenious norm, or det, or...?
                    % Convention: Rrel * V1 = V2, so Rrel = V2 * V1'
                    % The relative rotation is done wrt First? Camera reference frame
                    CR{1,1} = V_2{1,k} * V_1{1,k}';
                    CR{2,1} = V_2{1,k} * V_1{2,k}';
                    CR{1,2} = V_2{2,k} * V_1{1,k}';
                    CR{2,2} = V_2{2,k} * V_1{2,k}';
                    
                    % Test results in all the rest of triplets
%                     for ii=1:2
%                         for jj=1:2
%                             mm = ii + (jj-1)*2;
%                             for kk=1:Ntriplets
%                                 ang_dist(mm,kk) = angularDistance( ...
%                                     CR{ii,jj}*V_1{ii,kk},...
%                                     V_2{jj,kk} );
%                             end
% %                             keyboard
%                         end
%                     end
                    
                    % Get inliers using GT (to simplify problem of RANSAC)
                    R_gt = raw.frames(i2).pose.R * raw.frames(i1).pose.R';
                    gt_ang_dist = zeros(4,Ntriplets);
                    for ii=1:2
                        for jj=1:2
                            mm = ii + (jj-1)*2;
                            for kk=1:Ntriplets
                                gt_ang_dist(mm,kk) = angularDistance( ...
                                    R_gt*V_1{ii,kk},...
                                    V_2{jj,kk} );
                            end
%                             keyboard
                        end
                    end
                    
                    ang_thres = 1; % In deg
%                     [ Y,I ] = min( ang_dist );
%                     mask_thres = Y < ang_thres;
                    [ Y,I ] = min( gt_ang_dist );
                    mask_thres = Y < ang_thres;
                    
                    Ninliers = sum( mask_thres );
                    inliers1 = cell(1,Ntriplets);
                    inliers2 = cell(1,Ntriplets);
                    try
                    for kk=find(mask_thres)
                        switch I(kk)
                            case 1
                                inliers1{kk} = V_1{1,kk};
                                inliers2{kk} = V_2{1,kk};
                            case 2
                                inliers1{kk} = V_1{2,kk};
                                inliers2{kk} = V_2{1,kk};
                            case 3
                                inliers1{kk} = V_1{1,kk};
                                inliers2{kk} = V_2{2,kk};
                            case 4
                                inliers1{kk} = V_1{2,kk};
                                inliers2{kk} = V_2{2,kk};
                        end
                    end
                    catch
                        keyboard
                    end
                    
                    break
                end
                
                % Global Procrustes optimization
                D1 = [inliers1{:}];
                D2 = [inliers2{:}];
                
                if isempty(D1) || isempty(D2)
                    warning('No inliers found!');
                    
                    % Use groundtruth as relative rotation
                    R_cum = R_gt * R_cum;
                else
                    
                    % norm(D1-R'*D2,'fro')
                    % Compute through Procrustes problem:
                    [U,~,V] = svd( D2*D1' );
                    R = U*V';
                    global_err = angularDistance(R,R_gt);
                    err_(i) = angularDistance(R,R_gt);
                    err_Elqursh(i) = angularDistance(R_Elqursh,R_gt);
                    fprintf('%d: Relative error is: %f\n', i, err_(i));
                    fprintf('%d: Elqursh Rel err is: %f\n', i,...
                            err_Elqursh(i));
                    
                    % Cumulative rotation
                    R_cum = R * R_cum;
                    ERR_(i) = angularDistance(R_cum,raw.frames(i2).pose.R);
                    fprintf('%d: Absolute error is: %f\n', i, ERR_(i));
                    
                    % Plot inliers
                    for k = find(mask_thres)
                        h = tracker.segs(triplets(:,k)).plot(...
                            {'y','LineWidth',2});
                        delete(h);
                    end
                    
                    keyboard
                end
                
                % Store V for comparison with next frame
%                 V_prev  = V_1;
%                 a0_prev = a0;
                catch exception
                    warning(exception.message)
                    keyboard
                end
            end
        end
        function testFreiburg( this, dataset_folder, dataset_type,...
                               i0, for_step, debug )
            if ~exist('debug','var')
                debug = false;
            end
            
            % Get camera configuration
%             config_file = fullfile( pwd, 'configs', 'freiburg3RGB.ini' );
%             SConfigCam = readConfigFile( config_file );
%             this.Cam = CRealCamera( SConfigCam );
            
            % Load all existing images in dataset
%             dataset_folder = '/media/cloud/Datasets/rgbd_dataset_freiburg3_cabinet/';
%             raw = CRawlogCam( dataset_folder, [], 'Freiburg' );
            raw = CRawlogCam( dataset_folder, [], dataset_type );
            
            tracker = CGtracker;
            tracker.WITH_DEB = debug;
            % Skip tracking for stored steps
            
            figure( tracker.hFigure );
            im = raw.frames(1).loadImg;
            tracker.loadImage( im );
            tracker.hIm = imshow( tracker.img ); hold on;
            freezeColors;
            for i=i0(1):for_step:raw.Nobs-for_step % Step size 1
%             for i=1:raw.Nobs
                title(sprintf('Frame #%d',i));

                % Check if this iteration is already solved
                if exist( raw.frames(i).path_metafile, 'file' )
                    tracker.loadSegs( raw.frames(i).path_metafile );
                    if 1
                        im = raw.frames(i).loadImg;
                        tracker.loadImage( im );
                        set(tracker.hIm,'CData', tracker.img);
                        tags = tracker.segs.tags( tracker.maskSegs );
                        
                        if any(tracker.hSegs), delete( tracker.hSegs ), end
                        if any(tracker.hTags), delete( tracker.hTags ), end
                        [tracker.hSegs,tracker.hTags] = ...
                            tracker.segs.segs(tracker.maskSegs).plot('r', tags);
                        pause(0.1);
                        if 0
                            % Manually correct
                            tracker.addNetPts;
                            save(raw.frames(i).path_metafile,'tracker');
                        end
                    end
                    continue;
                end
                
                % Code continues if not solved yet:
                % ---------------------------------               
                % Load next image from rawlog
                im = raw.frames(i).loadImg;
                
                if isempty( tracker.segs )
                    % If there is no previous information,
                    % request user hint
                    tracker.loadImage( im );
                    
%                     tracker.hint;
                    tracker.hintNet;
                else
                    if isempty( tracker.img ) && i > 1
                        % Load the previous image to track
                        tracker.loadImage( raw.frames(i-1).loadImg );
                    end 
                    % If there was a previous image,
                    % update segments position
                    tracker.IAT_update( im );
                    % tracker.segs.plot('y')
                    
                    tracker.loadImage( im );
                end
                
                % Plot current figure
                if tracker.WITH_PLOT
                    set(tracker.hIm,'CData', tracker.img);
                    tags = tracker.segs.tags( tracker.maskSegs );
                    if any(tracker.hSegs), delete( tracker.hSegs ), end
                    if any(tracker.hTags), delete( tracker.hTags ), end
                    [tracker.hSegs,tracker.hTags] = ...
                        tracker.segs.segs(tracker.maskSegs).plot('y', tags);
                    % Set tag properties
                    set(tracker.hTags,'FontWeight','bold',...
                                      'FontSize',15);
                end
                
                % Optimize estimation by SVD method
                tracker.SVD_update;
                % tracker.addNetPts;
                if tracker.WITH_PLOT
%                     set(this.hFigure,'Position',[1111 401 808 570]);
%                     set(gcf,'Position',[482   284   808   570]);
%                     keyboard
                    pause(0.5);
                end
                
                % Save current results
                save(raw.frames(i).path_metafile,'tracker');
%                 temp_segs = tracker.segs;
%                 temp_mask = tracker.maskSegs;
%                 save( raw.frames(i).path_metafile, 'temp_segs', 'temp_mask' );
            end
        end
               
        %% Headers for method code
        % Header of method codeElqursh
        [Rrel, Vs, trel, triplets] = codeElqursh( this, segs1, segs2, matches, img_size,...
                     tracker1, tracker2 )
        % Header of method P3oA
%         [Rrel, Vs, trel] = codeP3oA( this, segs1, segs2, matches, K, rotThres )
        [Rrel, Vs, triplets] = codeP3oA( this, segs1, segs2, matches, K, rotThres )
        % Header of translation epipolar method (from Elqursh)
        [trel, pairs, pts] = codeTranslation( this, segs1_all, segs2_all, matches, Rrel, K, tranThres )
        % Header of scale registration method
        [s,pts3D] = codeReconstruction( this,...
                                im_pts,...
                                Rrel, trel, K, imsize_,...
                                reconThres )
                            
        %% Headers for experiments code
        [err_R] = testOrientation( this,...
            dataset_folder, dataset_type, i0, step, debug )
        
        function [err, global_err] = syntheticElqursh( this )
                       
            % IMPORTANT:
            % The convention used by Elqursh is that
            % computed R (unknown) is (^c)R(_w), that is,
            % rotation of World (equivalent to lines configuration)
            % seen from Camera
            % The R field of Cam is (^w)R(_c), so the GT rotation
            % for the Elqursh estimate is Cam.R' (transpose)
            R_gt = this.Cam.R';
            
            if this.WITH_PLOT
                figure(this.hFigure);
            end
            
            % Solve with Elqursh
            primitives = this.Cube.elqursh_primitives;
            Nprim = length(primitives);
            K = this.Cam.K;
            err = zeros(1,length(primitives));
            I = eye(3);
            cell_d = cell(1,Nprim);
            cell_v = cell(1,Nprim);

            for k=1:Nprim
                prim = primitives{k};
                
                if this.WITH_PLOT
                    subplot(this.hF_scene);
                    h_prim = this.Cube.plot_prim( prim );
                end
                
                prim2D = prim.project(this.Cam);
                if this.WITH_PLOT
                    subplot(this.hF_image);
                    prim2D.plot;
                end
                
                line = cell(1,3);
                for ii=1:3
                    line{ii} = prim(ii).projectLine( this.Cam );
                end
                v2 = cross( line{2}, line{3} );
                v1 = null( [ v2'*(inv(K)'*inv(K)) ; line{1}' ] );
                
                % Approximate solution, only valid for almost canonical
                % directions
                [~,dir1] = max(abs(prim(1).v));
                [~,dir2] = max(abs(prim(2).v));
                dir3 = setdiff(1:3,[dir1 dir2]);
                
                R = eye(3);
                R(:,dir1) = snormalize(K \ v1);
                R(:,dir2) = snormalize(K \ v2);
                switch dir3
                    case 1
                        R(:,1) = cross(R(:,2),R(:,3));
                    case 2
                        R(:,2) = cross(R(:,3),R(:,1));
                    case 3
                        R(:,3) = cross(R(:,1),R(:,2));
                end
                
                % Get good signs basing on dot-test and Ground Truth
                s = dot( R, R_gt, 1 );
                R = R * diag( sign(s) );

                % Error
                err(k) = angularDistance(R,R_gt);
                
                % Store vanishing points and directions for global Procrustes
                cell_d{k} = I(:,[dir1 dir2]);
                cell_v{k} = R(:,[dir1 dir2]); % Equivalent to inv(K)*K*rk
            end
            % Set camera image borders
            if this.WITH_PLOT
                subplot(this.hF_image);
                this.Cam.setImageBorder;
            end
            
            D1 = [cell_d{:}];
            D2 = [cell_v{:}];
            
            % Compute through Procrustes problem:
            [U,~,V] = svd( D2*D1' );
            R_glob = U*V';
            global_err = angularDistance(R_glob,R_gt);
        end    
        function [err, global_err, global_err_W] = syntheticP3oA( this )
            
            % IMPORTANT:
            % The convention used by P3oA is that
            % computed V (unknown) is (^c)R(_triplet), that is,
            % rotation or direction of World set of lines seen from Camera
            % The R field of Cam is (^w)R(_c), so the GT reference V_gt
            % for the P3oA estimate here is Cam.R' (transpose)
            V_gt = this.Cam.R';
            
            if this.WITH_PLOT
                figure(this.hFigure);
            end
            
            % Compute with P3oA method
            primitives = this.Cube.trihedron_primitives;
            Nprim = length(primitives);
            
            K = this.Cam.K;
            err = zeros(1,Nprim);
            cell_d = cell(1,Nprim);
            cell_v = cell(1,Nprim);

            % Build solver
            P3oA_solver = CP3oASolver( this.Cam.K );
            for k=1:Nprim
                prim = primitives{k};
                % Take care of segments orientation
                % (building a dextrorotatory system)
                for kk=1:3
                    % Valid only for canonical directions (simulation)
                    if any(prim(kk).v < 0)
                        prim(kk) = prim(kk).inverse;
                    end
                end
                
                if this.WITH_PLOT
                    subplot(this.hF_scene);
                    h_prim = this.Cube.plot_prim( prim );
                end
                
                prim2D = prim.project(this.Cam);
                if this.WITH_PLOT
                    subplot(this.hF_image);
                    prim2D.plot('-k',{'x','y','z'});
                end
                
                for ii=1:3
                    l = snormalize( prim(ii).projectLine( this.Cam ) ); % Image coordinates of line
                    
                    cell_n{ii} = snormalize( K' * l );
                    if 0
%                     if this.WITH_COVARIANCE
                        objs_l(ii) = Manifold.S2( snormalize(l) );
                        
                        % Compute lines uncertainty from points
                        p1h = [ prim2D(ii).p1; 1 ];
                        p2h = [ prim2D(ii).p2; 1 ];
                        % Store points object
                        A_p1h = this.lin_sd^2 * eye(3);
                        A_p1h(3,3) = 0; % Make covariance homogeneous 
                        A_p2h = this.lin_sd^2 * eye(3);
                        A_p2h(3,3) = 0; % Make covariance homogeneous 
                        l  = cross( p1h, p2h );
                        J_ = [-skew(p1h) skew(p2h)];
                        A_ = [A_p2h zeros(3,3);
                              zeros(3,3) A_p1h];
                        A_l = J_ * A_ * J_';
                        % Homogeneize
                        JJ = null(l') * null(l')';
                        A_lh = JJ * A_l * JJ;
                        objs_l(ii).setRepresentationCov( A_lh );
                        
%                         Am_l = this.lin_sd^2 * eye(2);
%                         objs_l(ii).setMinimalCov( Am_l );
%                         A_lh = null(l') * Am_l * null(l')';
                        J_n_l = Dsnormalize(K'*l) * K';
                        objs_n(ii) = Manifold.S2( cell_n{ii} );
                        objs_n(ii).setRepresentationCov( J_n_l * A_lh * J_n_l' );
                        % Temporary
%                         sd_n = 1e-6;
%                         objs_n(ii).setMinimalCov( sd_n * eye(2) );
                    end
                end
                
                Nbp = [cell_n{:}];
                if 1
                    % Check degenerate case first
%                     if P3oA_solver.isDegenerate(Nbp)
%                         V_tri = NaN(3);
%                     else
                        cell_V = P3oA_solver.generalSolve( Nbp );
                        V_tri = P3oA_solver.correctSignsDet( cell_V, prim2D, +1 );
                        
                        A_L = { prim2D.A_l }; % Collect list output of array CSegment2D get method
                        A_N = P3oA_solver.covProp_N_L( A_L, prim2D );
                        A_V = P3oA_solver.covProp_eps_N( A_N, Nbp, V_tri );

                        % Check connection between degeneracy and uncertainty
                        [~,d] = P3oA_solver.isDegenerate(Nbp);
                        if P3oA_solver.isDegenerate(Nbp)
                            % Remove unstable solution?
                            V_tri = NaN(3);
                            fprintf('Deg: %f\tDiscr: %f\tA_trace: %f\n',...
                                d,P3oA_solver.discriminant(Nbp),trace(A_V));
                        end
%                     end
                else
                    trihedronSolver = CTrihedronSolver( Nbp, K );
                    trihedronSolver.loadSegments( prim2D );
                    V_tri = trihedronSolver.solve;
                end
                if 0
%                 if this.WITH_COVARIANCE
                    trihedronSolver.loadCovariance( ...
                        {objs_n.A_X} );
                    trihedronSolver.computeCovariance;
                    obj_V = trihedronSolver.obj_V;
                    
                    WITH_MONTECARLO = false;
                    if WITH_MONTECARLO
                        keyboard
                        % Set manifold framework inputs                        
                        obj_L = Manifold.Dyn( objs_l(1), objs_l(2), objs_l(3) );
                        A_L = blkdiag( objs_l.A_x );
                        obj_L.setMinimalCov( A_L );
                        
                        obj_N = Manifold.Dyn( objs_n(1), objs_n(2), objs_n(3) );
                        obj_N.setMinimalCov( blkdiag( objs_n.A_x ) );
                        
                        obj_pts = Manifold.Rn( ...
                                    [prim2D(1).p1;...
                                     prim2D(1).p2;...
                                     prim2D(2).p1;...
                                     prim2D(2).p2;...
                                     prim2D(3).p1;...
                                     prim2D(3).p2] );
                        obj_pts.setMinimalCov( this.lin_sd^2*eye(12) );
                        
                        % Set temporary necessary variables
                        this.prim2D = prim2D;

%                         out = Manifold.MonteCarloSim( ...
%                             @(X)this.Fun_P3oA_Fast(X),...
%                             obj_L, 'Ref', obj_V, 'N', 1e3 );
%                         out = Manifold.MonteCarloSim( ...
%                             @(X)this.Fun_P3oA_Fast_N(X),...
%                             obj_N, 'Ref', obj_V, 'N', 1e4 );
                        out = Manifold.MonteCarloSim( ...
                            @(X)this.Fun_P3oA_Fast_pts(X),...
                            obj_pts, 'Ref', obj_V, 'N', 1e4 );
                        keyboard
                    end
                end
                               
                % Error
                err(k) = angularDistance(V_tri,V_gt);
                
                % Store vanishing points and directions for global Procrustes
                % Only if valid solution
                if isnan( V_tri )
                    cell_d{k} = [];
                    cell_v{k} = [];
                else
                    cell_d{k} = eye(3);
                    cell_v{k} = V_tri; % Equivalent to inv(K)*K*rk
                end
                
                if this.WITH_COVARIANCE
                    % Store weight according to covariance
%                     cell_w{k} = trace( obj_V.A_x ) * eye(3);
                    if isnan( V_tri )
                        cell_w{k} = [];
                    else
                        cell_w{k} = trace( A_V ) * eye(3);
                    end
                end
            end
            % Set camera image borders
            if this.WITH_PLOT
                subplot(this.hF_image);
                this.Cam.setImageBorder;
            end
            
            D1 = [cell_d{:}];
            D2 = [cell_v{:}];
                       
            % norm(D1-R*D2,'fro')
            % Compute through Procrustes problem:
            % Get the rotation (^1)R(_2) which takes directions in D2 and
            % transform them to same reference as D1
            % That's the same as the orientation of camera from World or
            % (^w)R(_c), so this is the transpose of V_gt
            [Ur,~,Vr] = svd( D1*D2' );
            R_pro = Ur*Vr';
            V = R_pro';
            global_err = angularDistance(V,V_gt);
            
            if this.WITH_COVARIANCE
                % Weight matrix
                W  = blkdiag( cell_w{:} );
    %             W  = W / trace(W);
                D1W = D1 / W;
                D2W = D2 / W;

                % Compute through weighted Procrustes problem:
                [Ur,~,Vr] = svd( D1W*D2W' );
                R_pro_W = Ur*Vr';
                V_W = R_pro_W';
                global_err_W = angularDistance(V_W,V_gt);
            else
                global_err_W = [];
            end
        end
        function [err_R] = syntheticOrientation( this )
            
            % IMPORTANT (about notations):
            % Since for Elqursh R_k = (^c)R(_w), the relative rotation
            % Rrel = R_2 * R_1' obtained is (^c2)R(_c1), that is,
            % the rotation of Cam1 see from Cam2 system of reference.
            % The result of their algorithm is therefore inverse (or transposed)
            % of the GT (or P3oA estimate) relative rotation used by us.
            % Assign variables from properties
            
            % Declare used structures in advance
%             R = struct('P3oA',[],'Elqu',[],'Fuse',[]);
%             t = struct('P3oA',[],'Elqu',[],'Fuse',[]);
            R = struct('P3oA',[],'Elqu',[]);
            t = struct('P3oA',[],'Elqu',[]);

            %% Generate data
            % Generate data for algorithms (segments)
            Cam1 = copy( this.Cam ); % Cam object in 1st frame
            Cam2 = copy( this.Cam ); % Cam object in 2nd frame
            % R_gt - The relative camera rotation existing among frames,
            % that is (c1^)R(_c2) (robotics criteria)
            R_gt = this.Rrel;
            t_gt = snormalize( this.trel );
            t_gt_norm = norm( this.trel );
            % Store GT value for use inside method
            CGT.R( R_gt ); % Use of persistent variable in class CGT
            CGT.t( t_gt ); % Use of persistent variable in class CGT

            % Set GT triplets (for P3oA method) (by visual inspection)
            idxs_GT = {[1 4 7]
                       [2 5 8]
                       [3 6 9]};
            % Get 3D GT segments
            segs3D_GT = [this.Cube.segments{:}];
            CGT.segs3D( segs3D_GT );
%             figure; hold on;
%             segs3D_GT.plot3('-k',{'1','2','3','4','5','6','7','8','9'});
%             axis equal

            triplets_GT = allcomb( idxs_GT{:} )';
            % Use fixed ordering: ascend order (since x-y-z id does not matter)
            triplets_GT = sort(triplets_GT,1,'ascend'); %#ok<UDIM>
            % Order columns
            triplets_GT = sortrows(triplets_GT')';
            % DEBUG: Store persistent value
            CGT.triplets(triplets_GT);
            
            % Get all simulated segments on Half Cube
            all_segments_3D = [this.Cube.segments{:}];
            Nsegs = numel(all_segments_3D); 
            
            % First projection is done with input Cam pose
            segs1 = all_segments_3D.project( Cam1 );
            % Update camera pose with GT relative transformation
            % R2 = R1 * Rrel -> rel rot is done wrt Camera#1 reference frame
            % t2 = t1 * (^w)R(_c1) * trel -> rel trans is given wrt
            % Camera#1 coordinate system, and must be first transformed to
            % World coordinate system
            Cam2.R = Cam1.R * this.Rrel;
            Cam2.t = Cam1.t + Cam1.R * this.trel;
            segs2 = all_segments_3D.project( Cam2 );
            
            % Code for plotting problem instance
            if this.WITH_PLOT
                figure(this.hFigure);
                
                % Plot 3D scene
                subplot(this.hF_scene); hold on;
                tags = cellfun(@(x)num2str(x), num2cell(1:numel(all_segments_3D)),...
                    'UniformOutput', false);
                all_segments_3D.plot( '-k', tags );
                
                % Plot 2D projections
                subplot(this.hF_image); hold on;
                segs1.plot( 'r', tags );
                segs2.plot( 'g', tags );
                Cam1.setImageBorder;
                
                % Plot GT 2D projections (without noise)
                IdealCam1 = copy(Cam1);
                IdealCam1.sd = 0;
                idealSegs1 = all_segments_3D.project( IdealCam1 );
                IdealCam2 = copy(Cam2);
                IdealCam2.sd = 0;
                idealSegs2 = all_segments_3D.project( IdealCam2 );
                idealSegs1.plot( 'k', tags );
                idealSegs2.plot( 'k', tags );
            end
            
            matches = repmat( 1:Nsegs, 2,1 );
            
            %% Compute relative estimates
            % Solve with Elqursh method
            [R.Elqu, V.Elqu, t.Elqu] = this.codeElqursh( segs1, segs2, matches', this.Cam.size );
            R.Elqu = R.Elqu'; % The output (^c2)R(_c1) is transposed to obtain (^c1)R(_c2) (see IMPORTANT note above)
            
            % Solve with P3oA method
            rotThres  = 1.5; % For rotation metric
            [R.P3oA, V.P3oA] = this.codeP3oA( segs1, segs2,...
                matches, this.Cam.K, rotThres );
                        
            if 0 % Temporally disabled
            % Fuse data from both methods
            V1 = [V.P3oA{1}, V.Elqu{1}];
            V2 = [V.P3oA{2}, V.Elqu{2}];
            % Test for outliers in fused set
            d = acosd( dot( V1, R.P3oA*V2, 1) );
            inliers = d < rotThres;
            % Keep only inliers
            V1 = V1(:,inliers);
            V2 = V2(:,inliers);
            % Compute fused rotation
            [Ur,~,Vr] = svd(V1*V2');
            if (det(Ur)*det(Vr)>=0), Sr = eye(3);
            else Sr = diag([1 1 -1]);
            end
            R.Fuse = Ur*Sr*Vr';
            end
            
            %% Compute relative error
            % Repeat operation on all cases
            fields  = fieldnames( R );
            Nfields = numel(fields);
            
            for k=1:Nfields
                f = fields{k};
                err_R.(f) = angularDistance(R.(f),R_gt);
            end
        end
        function err = syntheticOdometry( this )
            
            % IMPORTANT (about notations):
            % Since for Elqursh R_k = (^c)R(_w), the relative rotation
            % Rrel = R_2 * R_1' obtained is (^c2)R(_c1), that is,
            % the rotation of Cam1 see from Cam2 system of reference.
            % The result of their algorithm is therefore inverse (or transposed)
            % of the GT (or P3oA estimate) relative rotation used by us.
            % Assign variables from properties
            
            % Declare used structures in advance
            R = struct('P3oA',[],'Elqu',[],'Fuse',[]);
            t = struct('P3oA',[],'Elqu',[],'Fuse',[]);
            
            %% Generate data
            % Generate data for algorithms (segments)
            Cam1 = copy( this.Cam ); % Cam object in 1st frame
            Cam2 = copy( this.Cam ); % Cam object in 2nd frame
            % R_gt - The relative camera rotation existing among frames,
            % that is (c1^)R(_c2) (robotics criteria)
            R_gt = this.Rrel;
            t_gt = snormalize( this.trel );
            t_gt_norm = norm( this.trel );
            % Store GT value for use inside method
            CGT.R( R_gt ); % Use of persistent variable in class CGT
            CGT.t( t_gt ); % Use of persistent variable in class CGT

            % Set GT triplets (for P3oA method) (by visual inspection)
            idxs_GT = {[1 4 7]
                       [2 5 8]
                       [3 6 9]};
            % Get 3D GT segments
            segs3D_GT = [this.Cube.segments{:}];
            CGT.segs3D( segs3D_GT );
%             figure; hold on;
%             segs3D_GT.plot3('-k',{'1','2','3','4','5','6','7','8','9'});
%             axis equal

            triplets_GT = allcomb( idxs_GT{:} )';
            % Use fixed ordering: ascend order (since x-y-z id does not matter)
            triplets_GT = sort(triplets_GT,1,'ascend'); %#ok<UDIM>
            % Order columns
            triplets_GT = sortrows(triplets_GT')';
            % DEBUG: Store persistent value
            CGT.triplets(triplets_GT);
            
            % Get all simulated segments on Half Cube
            all_segments_3D = [this.Cube.segments{:}];
            Nsegs = numel(all_segments_3D); 
            
            % First projection is done with input Cam pose
            segs1 = all_segments_3D.project( Cam1 );
            % Update camera pose with GT relative transformation
            % R2 = R1 * Rrel -> rel rot is done wrt Camera#1 reference frame
            % t2 = t1 * (^w)R(_c1) * trel -> rel trans is given wrt
            % Camera#1 coordinate system, and must be first transformed to
            % World coordinate system
            Cam2.R = Cam1.R * this.Rrel;
            Cam2.t = Cam1.t + Cam1.R * this.trel;
            segs2 = all_segments_3D.project( Cam2 );
            
            % Code for plotting problem instance
            if this.WITH_PLOT
                figure(this.hFigure);
                
                % Plot 3D scene
                subplot(this.hF_scene); hold on;
                tags = cellfun(@(x)num2str(x), num2cell(1:numel(all_segments_3D)),...
                    'UniformOutput', false);
                all_segments_3D.plot( '-k', tags );
                
                % Plot 2D projections
                subplot(this.hF_image); hold on;
                segs1.plot( 'r', tags );
                segs2.plot( 'g', tags );
                Cam1.setImageBorder;
                
                % Plot GT 2D projections (without noise)
                IdealCam1 = copy(Cam1);
                IdealCam1.sd = 0;
                idealSegs1 = all_segments_3D.project( IdealCam1 );
                IdealCam2 = copy(Cam2);
                IdealCam2.sd = 0;
                idealSegs2 = all_segments_3D.project( IdealCam2 );
                idealSegs1.plot( 'k', tags );
                idealSegs2.plot( 'k', tags );
            end
            
            matches = repmat( 1:Nsegs, 2,1 );
            
            %% Compute relative estimates
            % Solve with Elqursh method
            [R.Elqu, V.Elqu, t.Elqu] = this.codeElqursh( segs1, segs2, matches', this.Cam.size );
            R.Elqu = R.Elqu'; % The output (^c2)R(_c1) is transposed to obtain (^c1)R(_c2) (see IMPORTANT note above)
            t.Elqu = - R.Elqu * t.Elqu; % Change criterion
            
            % Solve with P3oA method
            rotThres  = 1;
            [R.P3oA, V.P3oA] = this.codeP3oA( segs1, segs2,...
                matches, this.Cam.K, rotThres );
            tranThres = 0.1;
            [t.P3oA, ~, im_pts] = this.codeTranslation( segs1, segs2,...
                matches, R.P3oA, this.Cam.K, tranThres );
                        
            % Fuse data from both methods
            V1 = [V.P3oA{1}, V.Elqu{1}];
            V2 = [V.P3oA{2}, V.Elqu{2}];
            % Test for outliers in fused set
            d = acosd( dot( V1, R.P3oA*V2, 1) );
            inliers = d < rotThres;
            % Keep only inliers
            V1 = V1(:,inliers);
            V2 = V2(:,inliers);
            % Compute fused rotation
            [Ur,~,Vr] = svd(V1*V2');
            if (det(Ur)*det(Vr)>=0), Sr = eye(3);
            else Sr = diag([1 1 -1]);
            end
            R.Fuse = Ur*Sr*Vr';
            % Compute translation
            [t.Fuse] = this.codeTranslation( segs1, segs2,...
                matches, R.Fuse, this.Cam.K, tranThres );
            
            %% Compute relative error
            % Repeat operation on all cases
            fields  = fieldnames( R );
            Nfields = numel(fields);
            
            for k=1:Nfields
                f = fields{k};
                err.R.(f) = angularDistance(R.(f),R_gt);
                err.t.(f) = norm(t.(f) - t_gt) * t_gt_norm;
            end
        end
        
        function err = syntheticReconstruction( this )
            
            % IMPORTANT (about notations):
            % Since for Elqursh R_k = (^c)R(_w), the relative rotation
            % Rrel = R_2 * R_1' obtained is (^c2)R(_c1), that is,
            % the rotation of Cam1 see from Cam2 system of reference.
            % The result of their algorithm is therefore inverse (or transposed)
            % of the GT (or P3oA estimate) relative rotation used by us.
            % Assign variables from properties
            
            % Declare used structures in advance
            R = struct('P3oA',[],'Elqu',[],'Fuse',[]);
            t = struct('P3oA',[],'Elqu',[],'Fuse',[]);
            
            %% Generate data
            % Generate data for algorithms (segments)
            Cam1 = copy( this.Cam ); % Cam object in 1st frame
            Cam2 = copy( this.Cam ); % Cam object in 2nd frame
            Cam3 = copy( this.Cam ); % Cam object in 3rd frame
            % R_gt - The relative camera rotation existing among frames,
            % that is (c1^)R(_c2) (robotics criteria)
            R_gt = this.Rrel;
            t_gt = snormalize( this.trel );
            t_gt_norm = norm( this.trel );
            % Store GT value for use inside method
            CGT.R( R_gt ); % Use of persistent variable in class CGT
            CGT.t( t_gt ); % Use of persistent variable in class CGT

            % Set GT triplets (for P3oA method) (by visual inspection)
            idxs_GT = {[1 4 7]
                       [2 5 8]
                       [3 6 9]};
            % Get 3D GT segments
            segs3D_GT = [this.Cube.segments{:}];
            CGT.segs3D( segs3D_GT );
%             figure; hold on;
%             segs3D_GT.plot3('-k',{'1','2','3','4','5','6','7','8','9'});
%             axis equal

            triplets_GT = allcomb( idxs_GT{:} )';
            % Use fixed ordering: ascend order (since x-y-z id does not matter)
            triplets_GT = sort(triplets_GT,1,'ascend'); %#ok<UDIM>
            % Order columns
            triplets_GT = sortrows(triplets_GT')';
            % DEBUG: Store persistent value
            CGT.triplets(triplets_GT);
            
            % Get all simulated segments on Half Cube
            all_segments_3D = [this.Cube.segments{:}];
            Nsegs = numel(all_segments_3D); 
            
            % First projection is done with input Cam pose
            segs{1} = all_segments_3D.project( Cam1 );
            % Update camera pose with GT relative transformation
            % R2 = R1 * Rrel -> rel rot is done wrt Camera#1 reference frame
            % t2 = t1 * (^w)R(_c1) * trel -> rel trans is given wrt
            % Camera#1 coordinate system, and must be first transformed to
            % World coordinate system
            Cam2.R = Cam1.R * this.Rrel;
            Cam2.t = Cam1.t + Cam1.R * this.trel;
            segs{2} = all_segments_3D.project( Cam2 );
            % Yet update one more camera, #3 wrt #2
            % (for simplicity, use same rel GT for now)
            Cam3.R = Cam2.R * this.Rrel;
            Cam3.t = Cam2.t + Cam2.R * this.trel;
            segs{3} = all_segments_3D.project( Cam3 );
            
            colors = 'rgb';
            
            % Code for plotting problem instance
            if this.WITH_PLOT
                figure(this.hFigure);
                
                % Plot 3D scene
                subplot(this.hF_scene); hold on;
                tags = cellfun(@(x)num2str(x), num2cell(1:numel(all_segments_3D)),...
                    'UniformOutput', false);
                all_segments_3D.plot( '-k', tags );
                
                % Plot 2D projections
                subplot(this.hF_image); hold on;
                for k=1:3
                    segs{k}.plot( colors(k), tags );
                end
                Cam1.setImageBorder;
                
                % Plot GT 2D projections (without noise)
                IdealCam1 = copy(Cam1);
                IdealCam1.sd = 0;
                idealSegs1 = all_segments_3D.project( IdealCam1 );
                IdealCam2 = copy(Cam2);
                IdealCam2.sd = 0;
                idealSegs2 = all_segments_3D.project( IdealCam2 );
                IdealCam3 = copy(Cam3);
                IdealCam3.sd = 0;
                idealSegs3 = all_segments_3D.project( IdealCam3 );
                idealSegs1.plot( 'k', tags );
                idealSegs2.plot( 'k', tags );
                idealSegs3.plot( 'k', tags );
            end
            
            matches = repmat( 1:Nsegs, 2,1 );
            
            %% Compute relative estimates
            %# Solve with 1st pair (1-2) with P3oA method
            rotThres  = 1;
            [R.P3oA, V.P3oA] = this.codeP3oA( segs{1}, segs{2},...
                matches, this.Cam.K, rotThres );
%             tranThres = 0.1;
            tranThres = 1;
            [t.P3oA, pairs, im_pts] = this.codeTranslation( segs{1}, segs{2},...
                matches, R.P3oA, this.Cam.K, tranThres );
            
            % Code for 3D structure computation
            P{1} = this.Cam.K * eye(3) * [ eye(3) zeros(3,1) ]; % Camera matrix ref Cam1
%             P2 = this.Cam.K * R.P3oA' *[ eye(3)   -t.P3oA  ]; % Camera matrix for non-ref Cam2
            R12 = R.P3oA;
            t12 = t_gt_norm*t.P3oA;
            P{2} = this.Cam.K * R12' *[ eye(3) -t12  ]; % Camera matrix for non-ref Cam2
            imsize = [ this.Cam.size', this.Cam.size' ];
            Npts = size(im_pts{1},2);
%             pts3D = zeros(3, Npts);
            X = zeros(4, Npts);
            for i=1:Npts
                x = makeinhomogeneous( [ im_pts{1}(:,i), im_pts{2}(:,i) ] );
                X(:,i) = vgg_X_from_xP_lin(x,P,imsize);
%                 pts3D(:,i) = makeinhomogeneous( ...
%                     vgg_X_from_xP_lin(x,P,imsize) );
            end
            % Plot reconstruction
            mask_finite = abs(X(4,:)) > 0.01;
            pts3D{1} = makeinhomogeneous( X(:,mask_finite) );
            % Transform points to World coordinate system
            pts3D_W = this.Cam.R * pts3D{1} + repmat(this.Cam.t,1,size(pts3D{1},2));
            subplot( this.hF_scene )
            hold on, plot3(pts3D_W(1,:),pts3D_W(2,:),pts3D_W(3,:),'or')
            subplot( this.hF_image )

            %# Solve with 2nd pair (2-3) with P3oA method
            keyboard
            rotThres  = 1;
            [R.P3oA, V.P3oA] = this.codeP3oA( segs{2}, segs{3},...
                matches, this.Cam.K, rotThres );
            tranThres = 0.1;
            [t.P3oA, pairs, im_pts] = this.codeTranslation( segs{2}, segs{3},...
                matches, R.P3oA, this.Cam.K, tranThres );
            
            % Code for 3D structure computation
            P{1} = this.Cam.K * eye(3) * [ eye(3) zeros(3,1) ]; % Camera matrix ref Cam1
            P{2} = this.Cam.K * R.P3oA' *[ eye(3)   -t.P3oA  ]; % Camera matrix for non-ref Cam2
%             P{2} = this.Cam.K * R.P3oA' *[ eye(3) -t_gt_norm*t.P3oA  ]; % Camera matrix for non-ref Cam2
            imsize = [ this.Cam.size', this.Cam.size' ];
            Npts = size(im_pts{1},2);
%             pts3D = zeros(3, Npts);
            X = zeros(4, Npts);
            for i=1:Npts
                x = makeinhomogeneous( [ im_pts{1}(:,i), im_pts{2}(:,i) ] );
                X(:,i) = vgg_X_from_xP_lin(x,P,imsize);
%                 pts3D(:,i) = makeinhomogeneous( ...
%                     vgg_X_from_xP_lin(x,P,imsize) );
            end
            % Plot reconstruction
            mask_finite = abs(X(4,:)) > 0.01;
            pts3D{2} = makeinhomogeneous( X(:,mask_finite) );
            
            % Find scale factor for second trel
            A = pts3D{1} - repmat(t12,1,size(pts3D{1},2));
            B = R12 * pts3D{2};
            keyboard
            s = sum( dot(A,B,1) ) / sum( dot(B,B,1) );
            
            % Transform points to World coordinate system
            pts3D_W = this.Cam.R * this.Rrel * s * pts3D{2} +...
                repmat(this.Cam.t + this.Cam.R*this.trel,1,size(pts3D{2},2));
            subplot( this.hF_scene )
            hold on, plot3(pts3D_W(1,:),pts3D_W(2,:),pts3D_W(3,:),'*g')
            subplot( this.hF_image )
            
            %% Compute relative error
            % Repeat operation on all cases
% % %             keyboard
% % %             fields  = fieldnames( R );
% % %             Nfields = numel(fields);
% % %             
% % %             for k=1:Nfields
% % %                 f = fields{k};
% % %                 err.R.(f) = angularDistance(R.(f),R_gt);
% % %                 err.t.(f) = norm(t.(f) - t_gt) * t_gt_norm;
% % %             end
        end
        
        function V = Fun_P3oA_Fast( this, L )
            L = reshape( L.X, 3,3 );
            N = snormalize( this.Cam.K' * L );
            
            trihedronSolver = CTrihedronSolver( N, this.Cam.K );
            trihedronSolver.loadSegments( this.prim2D );
            V = trihedronSolver.solve;
            V = Manifold.SO3( V );
        end
        function V = Fun_P3oA_Fast_N( this, N )
            N = reshape( N.X, 3,3 );
            
            trihedronSolver = CTrihedronSolver( N, this.Cam.K );
            trihedronSolver.loadSegments( this.prim2D );
            V = trihedronSolver.solve;
            V = Manifold.SO3( V );
        end
        function V = Fun_P3oA_Fast_pts( this, obj_pts )
            pts = reshape(obj_pts.X,2,[]);
            Cpts = mat2cell(pts, 2, [2 2 2]);
            cell_n = cell(1,3);
            for ii=1:3
                p1h = [ Cpts{ii}(:,1); 1 ];
                p2h = [ Cpts{ii}(:,2); 1 ];
                l  = cross( p1h, p2h );
                cell_n{ii} = snormalize( this.Cam.K' * l );
            end
            N = [cell_n{:}];
            
            trihedronSolver = CTrihedronSolver( N, this.Cam.K );
            trihedronSolver.loadSegments( this.prim2D );
            V = trihedronSolver.solve;
            V = Manifold.SO3( V );
        end
        
        function saveVideo( this, dataset_folder )
            
            % Get rawlog data
            raw = CRawlogCam( dataset_folder, [], 'Freiburg' );

            tracker = CGtracker([],false);
                        
            %# create AVI object
            vidObj = VideoWriter('Vid_Freiburg_tracking.avi');
            vidObj.Quality = 100;
            vidObj.FrameRate = 33;
            open(vidObj);
            
            for i=1:raw.Nobs-1
                if ~exist( raw.frames(i).path_metafile, 'file' )
                    warning('Not processed lines in frame %d',i);
                    break
                end
                % Load segments for current step
                tracker.loadSegs( raw.frames(i).path_metafile );

                % Plot frame
                im = raw.frames(i).loadImg;
                tracker.loadImage( im );
                if ~exist('hIm','var')
                    figure('Name','Track figure');
                    hIm = imshow( tracker.img ); hold on;
                    freezeColors;
%                     set(gcf,'Position',...)
                else
                    set(hIm,'CData',tracker.img);
                end
                tags  = tracker.segs.tags( tracker.maskSegs );
                if exist('hSegs','var')
                    delete(hSegs);
                    delete(gSegs);
                end
                [hSegs, gSegs] = tracker.segs.segs(tracker.maskSegs).plot('r', tags);
                % Edite segment tags style:
                set(gSegs,'Color','y')
                set(gSegs,'FontWeight','bold')
                set(gSegs,'FontSize',15)
                
                %# create movie
                writeVideo(vidObj, getframe(gca));
            end
            close(gcf);
            
            %# save as AVI file, and open it using system video player
            close(vidObj);
            implay('Vid_Freiburg_tracking.avi');
        end
        
        function videoPoses( this, poses, object )
            % videoPoses( this, poses, cube )
            % cube is an optional input argument to plot the given object
            % in the scene too
            
            % See tracking of real camera
            f = 0.05;
            simCam = CSimCamera( eye(3), zeros(3,1),...
                     this.Cam.K, this.Cam.res, f, this.Cam.sd );
            
            % Create simulated cube
%             cube = CCube( 1 );
%             cube.plot3;

            if isa(poses,'CPose3D')
                % It is not a struct of different poses
                S = repmat( struct('poses',[]), 1, numel(poses) );
                for i=1:numel(poses)
                    S(i).poses = poses(i);
                end
                poses = S;
            end
            

            % Extract poses
            fields  = fieldnames( poses );
            Nfields = numel(fields);
            % Find non-empty poses
            C = {poses.(fields{1})};
            mask_empty = cellfun(@isempty,C);
            % Remove empty poses
            poses(mask_empty) = [];
            
%             for k=1:Nfields
%                 poses_.(fields{k}) = [poses.(fields{k})];
%             end
            figure('Name','Trajectories'); hold on;
            h = cell(3,numel(poses));
            g = cell(3,numel(poses));
            colors = {'k','r','g','b'};
            
            % Obtain and plot trajectory
            Ctraj = cell(Nfields,1);
            mask_nonexist = false(1,Nfields);
            for k=1:Nfields
                all_ = [poses.(fields{k})];
                if isempty(all_)
                    mask_nonexist(k) = true;
                    continue;
                end
%                 Ctraj{k} = [all_.t];
                traj_ = [all_.t];
                
                % Plot camera origin and trajectory
                plot3( traj_(1,:),traj_(2,:),traj_(3,:),...
                       '-*', 'Color', colors{k} );
            end
            clear all_;
                
            if exist('object','var')
                object.plot3;
            end
            
            for i=1:numel(poses)
                for k=1:Nfields
                    if mask_nonexist(k)
                        continue;
                    end
                    % Assign pose to camera
                    simCam.R = poses(i).(fields{k}).R;
                    simCam.t = poses(i).(fields{k}).t;
                    % Plot camera
                    h{k,i} = simCam.plot3_CameraFrustum( colors{k} );
                    
% % %                     % Plot camera origin
% % %                     cam_xyz = poses(i).(fields{k}).t;
% % %                     cam_xyz = num2cell( cam_xyz );
% % %                     plot3( cam_xyz{:}, '*', 'Color', colors{k} );
                    
                    % Add tag to pose
                    cam_xyz = poses(i).(fields{k}).t;
                    cam_xyz = num2cell( cam_xyz );
                    g{k,i} = text( cam_xyz{:}, num2str( i ) );
                    set(g{k,i},'Color',colors{k});
%                     set(g{k,i},'FontWeight','bold');
                    set(g{k,i},'FontSize',10);
                end
                pause(0.01)
%                 delete(h(:,i)); % Remove current handles
            end
            axis equal;
        end
    end
    
    methods (Static)
        function err_R = fuseData( err_R_1, err_R_2 )
            % Fuse data from different experiments into a singles matrix of
            % structures
            
            assert( all( size(err_R_1) == size(err_R_2) ) );
            s = size(err_R_1);
            err_R = repmat( struct(), s(1), s(2) );
            
            err_R_ = {err_R_1, err_R_2};
            for k=1:numel(err_R_)
                fields = fieldnames(err_R_{k});
                for kk=1:numel(fields)
                    f = fields{kk};
                    g = [f,'_',num2str(k)];
                    [err_R.(g)] = deal( err_R_{k}.(f) );
                end
            end
        end
        
        function testPlot( err_R, Cval, methods )
            
            Nx = numel(Cval);
            
            if ~exist('methods','var')
                methods.xlab = {'P3oA','Elqursh'};
                methods.leg  = {'P3oA','Elqursh'};
                methods.N    = numel(methods.xlab);
            end
            
%             err_R = reshape( [err.R], size(err) );
%             err_t = reshape( [err.t], size(err) );
            % Matrix of stacked data
            % Nd columns for each plotted method (Nd x methods.N)
            if isstruct( err_R )
                fields = fieldnames(err_R);
                cell_M = cell(1,methods.N);
                for k=1:methods.N
                    f = fields{k};
                    cell_M{k} = reshape( [err_R.(f)], size(err_R) );
                end
                M = cell2mat( cell_M );
            elseif ismatrix( err_R )
                M = err_R; % Already converted
            else
                error('Check input format')
            end                
            
            % Cval contains cell of X-value tags for each column of boxplot
            % {'M1x1','M2x1','M3x1',...,'M1xn','M2xn','M3xn'}
            Cval = repmat( Cval, 1, methods.N );
            % Ctag contains the string with method corresponding
            % to each column of data
            Ctag = repmat( methods.xlab, Nx, 1 );
            Ctag = Ctag(:)';
            
            % Parameters to control the position in X label
            Npos    = 5;    % gap between samples in X label
            pos_ini = 1;    % initial value in X label
            Nsep    = 0.5;  % gap between methods in X label
            % Load the vector of positions
            pos_aux = pos_ini:Npos:Npos*Nx;
            pos_    = pos_aux;
            for i = 1:methods.N-1
                pos_ = [pos_ pos_aux+i*Nsep]; %#ok<AGROW>
            end
            
            % Colors configuration
            c_blue = [51 51 255]/255;
            c_oran = [255 128 0]/255;
            c_gree = [102 255 102]/255;
            c_purp = [178 102 255]/255;
            colorPalette = [ c_blue
                             c_oran
                             c_gree
                             c_purp ];
            % Boxplot color:
            % i-th row is the RGB color for i-th column of data in the plot
            color = repmat(colorPalette(1:methods.N,:),Nx,1);
            
            h = figure; hold on;
            
            % Plot lines (first to put behing)
            median_ = nanmedian(M);
            for i = 1:methods.N
                x_ = pos_(1, Nx*(i-1)+1:Nx*i);
                y_ = median_(1, Nx*(i-1)+1:Nx*i);
                plot(x_,y_,'Color',color(i,:),'LineWidth',1.5);
            end
            
            % Plot boxplot
            boxplot(M,{Cval,Ctag},...
                'position',sort(pos_),'colors', color,...
                'factorgap',0,'whisker',0,'plotstyle','compact');
            
            % Remove the outliers
            if 1
                bp_ = findobj(h, 'tag', 'Outliers'); % Find handler
                set(bp_,'Visible','Off'); % Remove object
            end
                        
            % Plot legend
            Cleg = methods.leg;
            Clab = {Cval{1,1:Nx}};
%             set(gca,'YScale','log');
            set(gca,'XTickLabel',{' '});
            [legh,objh,outh,outm] = legend(Cleg,'Location','NorthEast');
            set(objh,'linewidth',3);
            set(gca,'XTick',pos_aux);
            set(gca,'XTickLabel',Clab);
        end
        
        function testPlotHist( M )
            
            % Colors configuration
            c_blue = [51 51 255]/255;
            c_oran = [255 128 0]/255;
            c_gree = [102 255 102]/255;
            colors = {c_blue, c_oran, c_gree};
            
            % Scaling value to get percentages
            scaling = diag( 1./sum( ~isnan(M), 1 ) );
            
            % Plot results
            h_ = figure; hold on;
            if 0
                % Plot histogram (log?)
                [N,X] = hist( M ); % Compute number of occurrences and bin centers
                
                % Normalize each method values scaling wrt total number of
                % elements
                N = N * scaling;
                
                % Plot bars figure
                bar(X,N,'hist');
%                 set(gca, 'Xscale', 'log')
                h = findobj(gca,'Type','patch');
                set(h(2),'FaceColor',c_blue,'EdgeColor','w'); % Elqursh
                set(h(1),'FaceColor',c_oran,'EdgeColor','w'); % P3oA
                legend('Elqursh','P3oA','Location','NorthEast')
            else
                % Nothing below 1e-15
                % Nothing above 1e-9
%                 edges = [0, logspace(-15,-9,7), +inf];
                edges = [0, logspace(-14,-10,5), +inf];
                N = histc( M, edges );
                
                % Normalize each method values scaling wrt total number of
                % elements
                N = N * scaling;
                
                % Plot bars figure
                bar(N);
                h = findobj(gca,'Type','patch');
                set(h(2),'FaceColor',c_blue,'EdgeColor','w'); % Elqursh
                set(h(1),'FaceColor',c_oran,'EdgeColor','w'); % P3oA
                [legh,objh,outh,outm] = legend('Elqursh','P3oA','Location','NorthEast')
%                 set(objh,'linewidth',3);
                
                % Axis
                set(gca,'xticklabel',...
                    {'','1e-15','1e-14','1e-13','1e-12','1e-11','1e-10','1e-9'})
            end
        end
        
        function testPlotFreiRot( err_R ) % TODO: Check working
            % Colors configuration
            c_blue = [51 51 255]/255;
            c_oran = [255 128 0]/255;
            c_gree = [102 255 102]/255;
            c_face_blue = [153 153 255]/255;
            c_face_oran = [255 204 153]/255;
            c_face_gree = [102 255 102]/255;
            color = {c_blue, c_oran};
            color_face = {c_face_blue,c_face_oran};
           
            m = 1; n = 2;
            figure('Name','Error of results'); hold on;
            % set(gcf, 'renderer', 'opengl')
            % Boxplots
            % subplot(m,n,1); hold on;
            % title('Boxplot of rotation angle errors');
            M_R = [ [err_R.P3oA]
                [err_R.Elqu] ]';
            boxplot(M_R, {'P3oA','Elqursh'},...
                'boxstyle','outline',...
                'whisker',1.5,...
                'factorgap',0,...
                'positions',[0.5 1]);
            
            % Style parameters
            LW = 2; % Line Width
            hBox = sort( findobj(gca,'Tag','Box') );
            hOut = sort( findobj(gca,'Tag','Outliers') );
            for k=1:2
                hFill(k) = patch(get(hBox(k),'XData'),get(hBox(k),'YData'),'k');
                set(hFill(k),'FaceColor',color_face{k});
                %     set(hFill(k),'FaceAlpha',0.5); % Only with OpenGL renderer
                set(hFill(k),'EdgeColor',color{k});
                set(hFill(k),'LineWidth',LW);
                
                set(hOut(k),'Marker','.');
                set(hOut(k),'Color',color{k});
            end
            Tags = {'Median','Lower Adjacent Value','Upper Adjacent Value',...
                'Lower Whisker','Upper Whisker'};
            for i=1:numel(Tags)
                h_ = sort( findobj(gca,'Tag',Tags{i}) );
                for k=1:2
                    set(h_(k),'Color',color{k},...
                        'LineWidth',LW,...
                        'LineStyle','-');
                end
            end
            hMed = sort( findobj(gca,'Tag','Median') );
            for k=1:2
                %     uistack(hMed(k),'bottom');
                h__ = plot( get(hMed(k),'XData'), get(hMed(k),'YData') );
                set(h__,'Color',color{k},...
                    'LineWidth',LW,...
                    'LineStyle','-');
            end
            ylabel('Rotation error (deg)');
                        
            %     'Outliers'
            %     'Median'
            %     'Box'
            %     'Lower Adjacent Value'
            %     'Upper Adjacent Value'
            %     'Lower Whisker'
            %     'Upper Whisker'
            
            % Histograms
            figure
            % subplot(m,n,2); hold on;
            % title('Histogram of rotation angle errors');
            % Continuous approximation
            % % ksdensity( M_R(:,1) )
            % % ksdensity( M_R(:,2) )
            % % h = findobj(gca,'Type','line');
            % % set(h(2),'Color',c_blue); % Elqursh
            % % set(h(1),'Color',c_oran); % P3oA
            % Discrete histogram
            xbinscenters = 0:0.1:2.5;
            [N] = hist( [[err_R.P3oA]
                [err_R.Elqu] ]', xbinscenters );
            % bar(xbinscenters,N./repmat(trapz(xbinscenters,N),size(N,1),1),'histc');
            bar(xbinscenters,N,'histc');
            h = sort(findobj(gca,'Type','patch'));
            for k=1:2
                set(h(k),'FaceColor',color{k},'EdgeColor','w');
            end
            % set(h(2),'FaceColor',c_oran,'EdgeColor','w'); % P3oA
            % set(h(1),'FaceColor',c_gree,'EdgeColor','w'); % Elqu
            % set(h(1),'FaceColor',c_gree,'EdgeColor','w'); % W-P3oA
            legend('P3oA','Elqursh','Location','NorthEast')
            xlabel('Rotation error (deg)');
            ylabel('Occurrences');
            axis_ = axis;
            axis_(2) = 2.5;
            axis(axis_);
                        
            if 0
                % Ordered representation wrt |trel|
                subplot(m,n,3); hold on;
                title('Representation of errors wrt |t_{rel}|');
                [dt,Idt] = sort(vec_t_norm,2,'ascend');
                % [N,bin] = histc(dt, [0.01 0.1 0.2 0.5]);
                plot( dt,[err_R(Idt).P3oA], 'r.' );
                plot( dt,[err_R(Idt).Elqu], 'g.' );
                % plot( dt,[err_R(Idt).Fuse], 'b.' );
                
                % Ordered representation wrt |Rrel|
                subplot(m,n,4); hold on;
                title('Representation of errors wrt |R_{rel}|');
                [dR,IdR] = sort(vec_R_norm,2,'ascend');
                plot( dR,[err_R(IdR).P3oA], 'r.' );
                plot( dR,[err_R(IdR).Elqu], 'g.' );
                % plot( dR,[err_R(IdR).Fuse], 'b.' );
            end
        end
    end
end

