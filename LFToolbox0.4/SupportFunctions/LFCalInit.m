% LFCalInit - initialize calibration estimate, called by LFUtilCalLensletCam
%
% Usage: 
%     CalOptions = LFCalInit( InputPath, CalOptions )
%     CalOptions = LFCalInit( InputPath )
%
% This function is called by LFUtilCalLensletCam to initialize a pose and camera model estimate
% given a set of extracted checkerboard corners.
% 
% Inputs:
% 
%     InputPath : Path to folder containing processed checkerboard images. Checkerboard corners must
%                 be identified prior to calling this function, by running LFCalFindCheckerCorners
%                 for example. This is demonstrated by LFUtilCalLensletCam.
% 
%     [optional] CalOptions : struct controlling calibration parameters, all fields are optional
%                   .SaveResult : Set to false to perform a "dry run"
%   .CheckerCornersFnamePattern : Pattern for finding checkerboard corner files, as generated by
%                                 LFCalFindCheckerCorners; %s is a placeholder for the base filename
%             .CheckerInfoFname : Name of the output file containing the summarized checkerboard
%                                 information
%                 .CalInfoFname : Name of the file containing an initial estimate, to be refined.
%                                 Note that this parameter is automatically set in the CalOptions
%                                 struct returned by LFCalInit
%                .ForceRedoInit : Forces the function to overwrite existing results
%
% Outputs :
% 
%     CalOptions struct as applied, including any default values as set up by the function.
% 
%     The checkerboard info file and calibration info file are the key outputs of this function.
% 
% See also:  LFUtilCalLensletCam, LFCalFindCheckerCorners, LFCalRefine

% Part of LF Toolbox v0.4 released 12-Feb-2015
% Copyright (c) 2013-2015 Donald G. Dansereau

function CalOptions = LFCalInit( InputPath, CalOptions )

%---Defaults---
CalOptions = LFDefaultField( 'CalOptions', 'SaveResult', true );
CalOptions = LFDefaultField( 'CalOptions', 'CheckerCornersFnamePattern', '%s__CheckerCorners.mat' );
CalOptions = LFDefaultField( 'CalOptions', 'CheckerInfoFname', 'CheckerboardCorners.mat' );
CalOptions = LFDefaultField( 'CalOptions', 'CalInfoFname', 'CalInfo.json' );
CalOptions = LFDefaultField( 'CalOptions', 'ForceRedoInit', false );


%---Start by checking if this step has already been completed---
fprintf('\n===Initializing calibration process===\n');
CalInfoSaveFname = fullfile(InputPath, CalOptions.CalInfoFname);
if( ~CalOptions.ForceRedoInit && exist(CalInfoSaveFname, 'file') )
    fprintf(' ---File %s already exists, skipping---\n', CalInfoSaveFname);
    return;
end

%---Compute ideal checkerboard geometry - order matters---
IdealCheckerX = CalOptions.ExpectedCheckerSpacing_m(1) .* (0:CalOptions.ExpectedCheckerSize(1)-1);
IdealCheckerY = CalOptions.ExpectedCheckerSpacing_m(2) .* (0:CalOptions.ExpectedCheckerSize(2)-1);
[IdealCheckerY, IdealCheckerX] = ndgrid(IdealCheckerY, IdealCheckerX);
IdealChecker = cat(3,IdealCheckerX, IdealCheckerY, zeros(size(IdealCheckerX)));
IdealChecker = reshape(IdealChecker, [], 3)';

%---Crawl folder structure locating corner info files---
fprintf('\n===Locating checkerboard corner files in %s===\n', InputPath);
[CalOptions.FileList, BasePath] = LFFindFilesRecursive( InputPath, sprintf(CalOptions.CheckerCornersFnamePattern, '*') );
fprintf('Found :\n');
disp(CalOptions.FileList)

%---Initial estimate of focal length---
fprintf('Initial estimate of focal length...\n');
SkippedFileCount = 0;
ValidSuperPoseCount = 0;
ValidCheckerCount = 0;
%---Process each checkerboard corner file---
for( iFile = 1:length(CalOptions.FileList) )
    ValidSuperPoseCount = ValidSuperPoseCount + 1;
    CurFname = CalOptions.FileList{iFile};
    [~,ShortFname] = fileparts(CurFname);
    fprintf('---%s [%3d / %3d]...', ShortFname, ValidSuperPoseCount+SkippedFileCount, length(CalOptions.FileList));
    
    load(fullfile(BasePath, CurFname), 'CheckerCorners', 'LFSize', 'CamInfo', 'LensletGridModel', 'DecodeOptions');
    PerImageValidCount = 0;
    for( TIdx = 1:size(CheckerCorners,1) )
        for( SIdx = 1:size(CheckerCorners,2) )
            CurChecker = CheckerCorners{TIdx, SIdx}';
            CurSize = size(CurChecker);
            CurValid = (CurSize(2) == prod(CalOptions.ExpectedCheckerSize));
            CheckerValid(ValidSuperPoseCount, TIdx, SIdx) = CurValid;
            
            %---For valid poses (having expected corner count), compute a homography---
            if( CurValid )
                ValidCheckerCount = ValidCheckerCount + 1;
                PerImageValidCount = PerImageValidCount + 1;
                
%                 %--- reorient to expected ---
%                 Centroid = mean( CurChecker,2 );
%                 IsTopLeft = all(CurChecker(:,1) < Centroid);
%                 IsTopRight = (CurChecker(1,1) > Centroid(1) && CurChecker(2,1) < Centroid(2));
%                 if( IsTopRight )
%                     CurChecker = reshape(CurChecker, [2, CalOptions.ExpectedCheckerSize]);
%                     CurChecker = CurChecker(:, end:-1:1, :);
%                     CurChecker = permute(CurChecker, [1,3,2]);
%                     CurChecker = reshape(CurChecker, 2, []);
%                 end
%                 IsTopLeft = all(CurChecker(:,1) < Centroid);
%                 assert( IsTopLeft, 'Error: unexpected point order from detectCheckerboardPoints' );

                %--- reorient to expected ---
                Centroid = mean( CurChecker,2 );
                IsTopLeft = all(CurChecker(:,1) < Centroid);
                IsTopRight = (CurChecker(1,1) > Centroid(1) && CurChecker(2,1) < Centroid(2));
                IsBotLeft = (CurChecker(1,1) < Centroid(1) && CurChecker(2,1) > Centroid(2));
                IsBotRight = all(CurChecker(:,1) > Centroid);
                if( IsTopRight )
                    CurChecker = reshape(CurChecker, [2, CalOptions.ExpectedCheckerSize]);
                    CurChecker = CurChecker(:, end:-1:1, :);
                    CurChecker = permute(CurChecker, [1,3,2]);
                    CurChecker = reshape(CurChecker, 2, []);
                elseif( IsBotLeft )
                    CurChecker = reshape(CurChecker, [2, CalOptions.ExpectedCheckerSize]);
                    CurChecker = CurChecker(:, :, end:-1:1);
                    CurChecker = permute(CurChecker, [1,3,2]);
                    CurChecker = reshape(CurChecker, 2, []);
                elseif( IsBotRight ) % untested case
                    CurChecker = reshape(CurChecker, [2, CalOptions.ExpectedCheckerSize]);
                    CurChecker = CurChecker(:, end:-1:1, end:-1:1);
                    CurChecker = permute(CurChecker, [1,3,2]);
                    CurChecker = reshape(CurChecker, 2, []);
                end
                IsTopLeft = all(CurChecker(:,1) < Centroid);
                assert( IsTopLeft, 'Error: unexpected point order from detectCheckerboardPoints' );
                
                CheckerObs{ValidSuperPoseCount, TIdx, SIdx} = CurChecker;
                
                %---Compute homography for each subcam pose---
                CurH = compute_homography( CurChecker, IdealChecker(1:2,:) );
                H(ValidCheckerCount, :,:) = CurH;
            end
        end
    end
    CalOptions.ValidSubimageCount(iFile) = PerImageValidCount;
    fprintf(' %d / %d valid.\n', PerImageValidCount, prod(LFSize(1:2)));
end

A = [];
b = [];

%---Initialize principal point at the center of the image---
% This section of code is based heavily on code from the Camera Calibration Toolbox for Matlab by
% Jean-Yves Bouguet
CInit = LFSize([4,3])'/2 - 0.5; 
RecenterH = [1, 0, -CInit(1); 0, 1, -CInit(2); 0, 0, 1];

for iHomography = 1:size(H,1)
    CurH = squeeze(H(iHomography,:,:));
    CurH = RecenterH * CurH;
     
    %---Extract vanishing points (direct and diagonal)---
    V_hori_pix = CurH(:,1);
    V_vert_pix = CurH(:,2);
    V_diag1_pix = (CurH(:,1)+CurH(:,2))/2;
    V_diag2_pix = (CurH(:,1)-CurH(:,2))/2;
    
    V_hori_pix = V_hori_pix/norm(V_hori_pix);
    V_vert_pix = V_vert_pix/norm(V_vert_pix);
    V_diag1_pix = V_diag1_pix/norm(V_diag1_pix);
    V_diag2_pix = V_diag2_pix/norm(V_diag2_pix);
    
    a1 = V_hori_pix(1);
    b1 = V_hori_pix(2);
    c1 = V_hori_pix(3);
    
    a2 = V_vert_pix(1);
    b2 = V_vert_pix(2);
    c2 = V_vert_pix(3);
    
    a3 = V_diag1_pix(1);
    b3 = V_diag1_pix(2);
    c3 = V_diag1_pix(3);
    
    a4 = V_diag2_pix(1);
    b4 = V_diag2_pix(2);
    c4 = V_diag2_pix(3);
    
    CurA = [a1*a2, b1*b2; a3*a4, b3*b4];
    CurB = -[c1*c2; c3*c4];

    if( isempty(find(isnan(CurA), 1)) && isempty(find(isnan(CurB), 1)) )
        A = [A; CurA];
        b = [b; CurB];
    end
end

FocInit = sqrt(b'*(sum(A')') / (b'*b)) * ones(2,1);
fprintf('Init focal length est: %.2f, %.2f\n', FocInit);

%---Initial estimate of extrinsics---
fprintf('\nInitial estimate of extrinsics...\n');

for( iSuperPoseIdx = 1:ValidSuperPoseCount )
    fprintf('---[%d / %d]', iSuperPoseIdx, ValidSuperPoseCount);
    for( TIdx = 1:size(CheckerCorners,1) )
        fprintf('.');
        for( SIdx = 1:size(CheckerCorners,2) )
            if( ~CheckerValid(iSuperPoseIdx, TIdx, SIdx) )
                continue;
            end
            CurChecker = CheckerObs{iSuperPoseIdx, TIdx, SIdx};
            
            [CurRot, CurTrans] = compute_extrinsic_init(CurChecker, IdealChecker, FocInit, CInit, zeros(1,5), 0);
            [CurRot, CurTrans] = compute_extrinsic_refine(CurRot, CurTrans, CurChecker, IdealChecker, FocInit, CInit, zeros(1,5), 0,20,1000000);
            
            RotVals{iSuperPoseIdx, TIdx, SIdx} = CurRot;
            TransVals{iSuperPoseIdx, TIdx, SIdx} = CurTrans;
        end
    end
    
    %---Approximate each superpose as the median of its sub-poses---
    % note the approximation in finding the mean orientation: mean of rodrigues... works because all
    % sub-orientations within a superpose are nearly identical.
    MeanRotVals(iSuperPoseIdx,:) = median([RotVals{iSuperPoseIdx, :, :}], 2);
    MeanTransVals(iSuperPoseIdx,:) = median([TransVals{iSuperPoseIdx, :, :}], 2);
    fprintf('\n');
    
    %---Track the apparent "baseline" of the camera at each pose---
    CurDist = bsxfun(@minus, [TransVals{iSuperPoseIdx, :, :}], MeanTransVals(iSuperPoseIdx,:)');
    CurAbsDist = sqrt(sum(CurDist.^2));
    % store as estimated diameter; the 3/2 comes from the mean radius of points on a disk (2R/3)
    BaselineApprox(iSuperPoseIdx) = 2 * 3/2 * mean(CurAbsDist); 
end

%---Initialize the superpose estimates---
EstCamPosesV = [MeanTransVals, MeanRotVals];

%---Estimate full intrinsic matrix---
ST_IJ_SlopeApprox = mean(BaselineApprox) ./ (LFSize(2:-1:1)-1);
UV_KL_SlopeApprox = 1./FocInit';

EstCamIntrinsicsH = eye(5);
EstCamIntrinsicsH(1,1) = ST_IJ_SlopeApprox(1);
EstCamIntrinsicsH(2,2) = ST_IJ_SlopeApprox(2);
EstCamIntrinsicsH(3,3) = UV_KL_SlopeApprox(1);
EstCamIntrinsicsH(4,4) = UV_KL_SlopeApprox(2);

% Force central ray as s,t,u,v = 0, note all indices start at 1, not 0
EstCamIntrinsicsH = LFRecenterIntrinsics( EstCamIntrinsicsH, LFSize );

fprintf('\nInitializing estimate of camera intrinsics to: \n');
disp(EstCamIntrinsicsH);

%---Start with no distortion estimate---
EstCamDistortionV = [];

%---Optionally save the results---
if( CalOptions.SaveResult )
    TimeStamp = datestr(now,'ddmmmyyyy_HHMMSS');
    GeneratedByInfo = struct('mfilename', mfilename, 'time', TimeStamp, 'VersionStr', LFToolboxVersion);

    CheckerSaveFname = fullfile(BasePath, CalOptions.CheckerInfoFname);
    fprintf('\nSaving to %s...\n', CheckerSaveFname);
    save(CheckerSaveFname, 'GeneratedByInfo', 'CalOptions', 'CheckerObs', 'IdealChecker', 'LFSize', 'CamInfo', 'LensletGridModel', 'DecodeOptions');
    
    fprintf('Saving to %s...\n', CalInfoSaveFname);
    LFWriteMetadata(CalInfoSaveFname, LFVar2Struct(GeneratedByInfo, LensletGridModel, EstCamIntrinsicsH, EstCamDistortionV, EstCamPosesV, CamInfo, CalOptions, DecodeOptions));
end

fprintf(' ---Calibration initialization done---\n');
