function test_beamforming_extended
if ispc
  datadir = 'H:\common\matlab\fieldtrip\data\ftp\tutorial\sensor_analysis';
  mridir  = 'H:\common\matlab\fieldtrip\data\ftp\tutorial\beamformer_extended';
  templatedir  = 'H:/common/matlab/fieldtrip/template/sourcemodel';
elseif isunix
  datadir = '/home/common/matlab/fieldtrip/data/ftp/tutorial/sensor_analysis';
  mridir = '/home/common/matlab/fieldtrip/data/ftp/tutorial/beamformer_extended';
  templatedir  = '/home/common/matlab/fieldtrip/template/sourcemodel';
end

load(fullfile(datadir, 'subjectK.mat'));

% Time windows of interest
data = ft_appenddata([], data_left, data_right);
cfg = [];                                           
cfg.toilim = [-0.8 1.1];           
cfg.minlength = 'maxperlen';
data = ft_redefinetrial(cfg, data);


cfg = [];                                           
cfg.toilim = [-0.8 0];                       
data_bsl = ft_redefinetrial(cfg, data);
     
cfg.toilim = [0.3 1.1];                       
data_exp = ft_redefinetrial(cfg, data);

cfg = [];
data_cmb = ft_appenddata(cfg, data_bsl, data_exp);
% code the trial: 0 = baseline, 1 = experimental condition
data_cmb.trialinfo = [zeros(length(data_bsl.trial), 1); ones(length(data_exp.trial), 1)];
%% calculating the cross spectral density matrix
cfg = [];
cfg.method        = 'mtmfft';
cfg.output        = 'fourier'; % add hint: why fourier?
cfg.tapsmofrq     = 15;
cfg.foi           = 55;
cfg.keeptrials    = 'yes';
freq_cmb = ft_freqanalysis(cfg, data_cmb);

cfg = [];
cfg.trials = freq_cmb.trialinfo == 0;
freq_bsl = ft_selectdata(cfg, freq_cmb);
freq_bsl.cumtapcnt = freq_cmb.cumtapcnt(cfg.trials);
freq_bsl.cumsumcnt = freq_cmb.cumsumcnt(cfg.trials);
cfg.trials = freq_cmb.trialinfo == 1;
freq_exp = ft_selectdata(cfg, freq_cmb);
freq_exp.cumtapcnt = freq_cmb.cumtapcnt(cfg.trials);
freq_exp.cumsumcnt = freq_cmb.cumsumcnt(cfg.trials);

%%foward model and lead field

mri = ft_read_mri(fullfile(mridir, 'subjectK.mri'));
cfg = [];
cfg.coordsys   = 'ctf'; % our data is CTF MEG data
[segmentedmri] = ft_volumesegment(cfg, mri);

oldsegmented = load(fullfile(mridir, 'segmentedmri.mat'));
assert(isequal(rmfield(oldsegmented.segmentedmri, 'cfg'), rmfield(segmentedmri, 'cfg')), 'segmentation differs from stored data');

%save segmentedmri segmentedmri


% add anatomical information to the segmentation
segmentedmri.transform = mri.transform;
segmentedmri.anatomy   = mri.anatomy;
% call ft_sourceplot
cfg = [];
cfg.funparameter = 'gray';
ft_sourceplot(cfg,segmentedmri);

% create ht head model from the segmented brain surface
cfg = [];
cfg.method = 'singleshell';
hdm = ft_prepare_headmodel(cfg, segmentedmri);


template = load(fullfile(templatedir, 'standard_grid3d8mm')); 
% inverse-warp the subject specific grid to the template grid cfg = [];
cfg.grid.warpmni   = 'yes';
cfg.grid.template  = template.grid;
cfg.grid.nonlinear = 'yes'; % use non-linear normalization
cfg.mri            = mri;
sourcemodel        = ft_prepare_sourcemodel(cfg);


figure;
hold on;
% note that when calling different plotting routines, all objects that we plot 
% need to be in the same unit and coordinate space, here, we need to transform 
% the head model to 'cm'
ft_plot_vol(ft_convert_units(hdm, freq_cmb.grad.unit), 'edgecolor', 'none'); 
alpha 0.4;
ft_plot_mesh(sourcemodel.pos(sourcemodel.inside,:));
ft_plot_sens(freq_cmb.grad);

cfg         = [];
cfg.grid    = sourcemodel;
cfg.vol     = hdm;
cfg.channel = {'MEG'};
cfg.grad    = freq_cmb.grad;
sourcemodel_lf     = ft_prepare_leadfield(cfg, freq_cmb);


%% contrasting source activity
cfg              = [];
cfg.frequency    = freq_cmb.freq;
cfg.grad         = freq_cmb.grad;
cfg.method       = 'dics';
cfg.keeptrials   = 'yes';
cfg.grid         = sourcemodel_lf;
cfg.vol          = hdm;
cfg.keeptrials   = 'yes';
cfg.lambda       = '5%';
cfg.keepfilter   = 'yes';
cfg.fixedori     = 'yes';
cfg.realfilter   = 'yes';
source  = ft_sourceanalysis(cfg, freq_cmb);

% beam pre- and poststim by using the common filter
cfg.grid.filter   = source.avg.filter;
source_bsl  = ft_sourceanalysis(cfg, freq_bsl);
source_exp  = ft_sourceanalysis(cfg, freq_exp);

source_diff = source_exp;
source_diff.avg.pow = (source_exp.avg.pow ./ source_bsl.avg.pow) - 1;
source_diff.pos = template.grid.pos;
source_diff.dim = template.grid.dim;

% note that the exact directory is user-specific
if isunix
  templatefile = '/home/common/matlab/fieldtrip/external/spm8/templates/T1.nii';
elseif ispc
  templatefile = 'H:\common\matlab\fieldtrip\external\spm8\templates/T1.nii';
end
template_mri = ft_read_mri(templatefile);
cfg              = [];
cfg.voxelcoord   = 'no';
cfg.parameter    = 'avg.pow';
cfg.interpmethod = 'nearest';
cfg.coordsys     = 'mni';
source_diff_int  = ft_sourceinterpolate(cfg, source_diff, template_mri);

cfg               = [];
cfg.method        = 'slice';
cfg.coordsys      = 'mni';
cfg.funparameter  = 'avg.pow';
cfg.maskparameter = cfg.funparameter;
cfg.funcolorlim   = [0.0 1.2];
cfg.opacitylim    = [0.0 1.2]; 
cfg.opacitymap    = 'rampup';  
ft_sourceplot(cfg,source_diff_int);

cfg.method = 'ortho';
if isunix
  cfg.atlas           = '/home/common/matlab/spm8/toolbox/wfu_pickatlas/MNI_atlas_templates/aal_MNI_V4.img';
elseif ispc
  cfg.atlas           = 'H:/common/matlab/spm8/toolbox/wfu_pickatlas/MNI_atlas_templates/aal_MNI_V4.img';
end
ft_sourceplot(cfg,source_diff_int);

cfg.method = 'surface';
cfg.projmethod     = 'nearest'; 
cfg.surffile       = 'surface_l4_both.mat';
cfg.surfdownsample = 10;
ft_sourceplot(cfg,source_diff_int);


%% coherence beaming

data = ft_appenddata([], data_left, data_right);
cfg                 = [];
cfg.toilim          = [-1 -0.0025];
cfg.minlength       = 'maxperlen'; % this ensures all resulting trials are equal length
data_stim           = ft_redefinetrial(cfg, data);

cfg                 = [];
cfg.output          = 'powandcsd';
cfg.method          = 'mtmfft';
cfg.taper           = 'dpss';
cfg.tapsmofrq       = 5;
cfg.foi             = 20;
cfg.keeptrials      = 'yes';
cfg.channel         = {'MEG' 'EMGlft' 'EMGrgt'};
cfg.channelcmb      = {'MEG' 'MEG'; 'MEG' 'EMGlft'; 'MEG' 'EMGrgt'};
freq_csd            = ft_freqanalysis(cfg, data_stim);

cfg                 = [];
cfg.method          = 'dics';
cfg.refchan         = 'EMGlft';
cfg.frequency       = 20;
cfg.vol             = hdm;
cfg.grid            = sourcemodel;
source_coh_lft      = ft_sourceanalysis(cfg, freq_csd);

source_coh_lft.pos = template.grid.pos;
source_coh_lft.dim = template.grid.dim;


% note that the exact directory is user-specific
if isunix
  templatefile = '/home/common/matlab/fieldtrip/external/spm8/templates/T1.nii';
elseif ispc
  templatefile = 'H:\common\matlab\fieldtrip\external\spm8\templates/T1.nii';
end
template_mri = ft_read_mri(templatefile);
cfg              = [];
cfg.voxelcoord   = 'no';
cfg.parameter    = 'coh';
cfg.interpmethod = 'nearest';
cfg.coordsys     = 'mni';
source_coh_int   = ft_sourceinterpolate(cfg, source_coh_lft, template_mri);

cfg              = [];
cfg.method       = 'ortho';
cfg.coordsys     = 'mni';
cfg.funparameter = 'coh';
if isunix
  cfg.atlas           = '/home/common/matlab/spm8/toolbox/wfu_pickatlas/MNI_atlas_templates/aal_MNI_V4.img';
elseif ispc
  cfg.atlas           = 'H:/common/matlab/spm8/toolbox/wfu_pickatlas/MNI_atlas_templates/aal_MNI_V4.img';
end
figure; ft_sourceplot(cfg, source_coh_int);
end