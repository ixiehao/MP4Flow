const copy = {
  zh: {
    navFeatures: "功能", navWorkflow: "使用方式", navDownload: "下载",
    eyebrow: "为 macOS 而做的视频转换", heroTitle: "把视频变成 MP4，<br />简单这件事。",
    heroIntro: "免费、开源、本地处理。不上传视频，不要求账户，也不把编码参数丢给你。",
    download: "免费下载", viewSource: "查看源代码 <span aria-hidden=\"true\">↗</span>", heroSystemNote: "macOS 13+", installGuide: "安装 FFmpeg",
    stageCaption: "添加文件，选择质量，开始转换。",
    principleOneTitle: "视频留在你的 Mac", principleOneBody: "转换在本机完成；MP4Flow 不上传你的素材。",
    principleTwoTitle: "能快就不重编码", principleTwoBody: "兼容时直接封装；需要转码时优先使用 Apple 硬件能力。",
    principleThreeTitle: "没有订阅与水印", principleThreeBody: "项目以 MIT 许可证开源，功能没有付费墙。",
    featuresEyebrow: "日常需要的，刚刚好", featuresTitle: "少一点设置，<br />多一点确定性。",
    featureOneTitle: "智能转换", featureOneBody: "为常见视频选择兼容的 MP4 路径，尽可能避免多余的重编码。",
    featureTwoTitle: "剪切、裁切、旋转", featureTwoBody: "在队列中完成轻量编辑，精确到帧地选择剪切范围。",
    featureThreeTitle: "批量而可靠", featureThreeBody: "查看进度、重试失败任务、取消任务，并安全地保留原文件。",
    featureFourTitle: "适合你的分辨率", featureFourBody: "保持原画，或按视频自身尺寸选择 480P、720P、1080P 与更高目标。",
    featureFiveTitle: "实验性智能增强", featureFiveBody: "在兼容的 Apple 芯片与 macOS 27+ 上，可使用系统 VideoToolbox 超分能力。",
    featureSixTitle: "持续改进", featureSixBody: "开源开发，欢迎提交问题、测试边缘素材，或一起完善工具。",
    workflowEyebrow: "从文件到可播放 MP4", workflowTitle: "三步完成。",
    stepOneTitle: "添加视频", stepOneBody: "拖入文件，或从 Finder 选择素材。",
    stepTwoTitle: "选择结果", stepTwoBody: "用清晰的预设选择质量、尺寸与输出位置。",
    stepThreeTitle: "开始转换", stepThreeBody: "进度清晰可见，完成后可直接在 Finder 中查看。",
    downloadEyebrow: "从 GitHub 获取", downloadTitle: "让视频转换回归简单。",
    downloadBody: "下载最新版本，或从源代码构建。MP4Flow 始终免费、开源，并在你的 Mac 上运行。",
    getLatest: "获取最新版本", starGithub: "在 GitHub 关注 <span aria-hidden=\"true\">↗</span>",
    footerTagline: "原生 macOS 视频转 MP4 工具。", footerGithub: "GitHub", footerPrivacy: "隐私", footerLicense: "MIT 许可证",
    installEyebrow: "开始转换前", installTitle: "安装 FFmpeg", installIntro: "MP4Flow 使用 FFmpeg 与 ffprobe 读取和转换视频。通过 Homebrew 安装时，两者会一并安装。", installStepOne: "打开「终端」应用。", installStepTwo: "输入以下命令：", installStepThree: "安装完成后，重新打开 MP4Flow。", installHelp: "还没有 Homebrew？请先访问 <a href=\"https://brew.sh/\" target=\"_blank\" rel=\"noreferrer\">brew.sh</a> 安装。"
  },
  en: {
    navFeatures: "Features", navWorkflow: "How it works", navDownload: "Download",
    eyebrow: "VIDEO CONVERSION FOR macOS", heroTitle: "Video to MP4.<br />Nothing extra.",
    heroIntro: "Free, open source, and processed locally. No uploads, no accounts, and no codec jargon in your way.",
    download: "Download free", viewSource: "View source <span aria-hidden=\"true\">↗</span>", heroSystemNote: "macOS 13+", installGuide: "Install FFmpeg",
    stageCaption: "Add a file. Choose quality. Convert.",
    principleOneTitle: "Your videos stay on your Mac", principleOneBody: "Conversion happens locally. MP4Flow never uploads your media.",
    principleTwoTitle: "Fast when it can be", principleTwoBody: "Compatible files are remuxed directly; re-encoding prefers Apple hardware.",
    principleThreeTitle: "No subscription. No watermark.", principleThreeBody: "MIT-licensed open source, with no feature paywall.",
    featuresEyebrow: "JUST WHAT YOU NEED", featuresTitle: "Fewer settings.<br />More certainty.",
    featureOneTitle: "Smart Convert", featureOneBody: "Chooses a compatible MP4 path for common videos and avoids needless re-encoding where possible.",
    featureTwoTitle: "Trim, crop, rotate", featureTwoBody: "Make quick edits in the queue and choose a trim range with frame-level precision.",
    featureThreeTitle: "Reliable batches", featureThreeBody: "See progress, retry failed work, cancel safely, and keep the original files intact.",
    featureFourTitle: "Resolution that fits", featureFourBody: "Keep the original or select 480p, 720p, 1080p, and higher targets to suit the source.",
    featureFiveTitle: "Experimental Smart Enhance", featureFiveBody: "On supported Apple silicon Macs running macOS 27+, use system VideoToolbox super resolution.",
    featureSixTitle: "Open to improve", featureSixBody: "Built in the open. Report issues, test difficult media, or help make the tool better.",
    workflowEyebrow: "FROM FILE TO PLAYABLE MP4", workflowTitle: "Three steps.",
    stepOneTitle: "Add video", stepOneBody: "Drop in a file or choose media from Finder.",
    stepTwoTitle: "Choose your result", stepTwoBody: "Use clear presets for quality, size, and output location.",
    stepThreeTitle: "Start converting", stepThreeBody: "Follow the progress, then reveal the completed file in Finder.",
    downloadEyebrow: "GET IT ON GITHUB", downloadTitle: "Make video conversion simple again.",
    downloadBody: "Download the latest release or build it from source. MP4Flow is free, open source, and runs on your Mac.",
    getLatest: "Get the latest release", starGithub: "Follow on GitHub <span aria-hidden=\"true\">↗</span>",
    footerTagline: "Native video-to-MP4 conversion for macOS.", footerGithub: "GitHub", footerPrivacy: "Privacy", footerLicense: "MIT License",
    installEyebrow: "BEFORE YOU CONVERT", installTitle: "Install FFmpeg", installIntro: "MP4Flow uses FFmpeg and ffprobe to read and convert video. Installing with Homebrew adds both tools.", installStepOne: "Open the Terminal app.", installStepTwo: "Run this command:", installStepThree: "When it finishes, reopen MP4Flow.", installHelp: "Need Homebrew first? Install it from <a href=\"https://brew.sh/\" target=\"_blank\" rel=\"noreferrer\">brew.sh</a>."
  }
};

const languageButton = document.querySelector(".language-switch");
const languageLabel = document.querySelector("#language-label");
let language = navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";

function applyLanguage(nextLanguage) {
  language = nextLanguage;
  const translations = copy[language];
  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  document.title = language === "zh" ? "MP4Flow — 原生 macOS 视频转 MP4 工具" : "MP4Flow — Native video to MP4 for macOS";
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    element.innerHTML = translations[element.dataset.i18n];
  });
  document.querySelectorAll("[data-i18n-html]").forEach((element) => {
    element.innerHTML = translations[element.dataset.i18nHtml];
  });
  languageLabel.textContent = language === "zh" ? "EN" : "中文";
  languageButton.setAttribute("aria-label", language === "zh" ? "Switch to English" : "切换到中文");
}

languageButton.addEventListener("click", () => applyLanguage(language === "zh" ? "en" : "zh"));
const installDialog = document.querySelector("#install-dialog");
document.querySelector("#install-guide-trigger").addEventListener("click", () => installDialog.showModal());
document.querySelector("#install-dialog-close").addEventListener("click", () => installDialog.close());
installDialog.addEventListener("click", (event) => {
  if (event.target === installDialog) installDialog.close();
});
applyLanguage(language);
