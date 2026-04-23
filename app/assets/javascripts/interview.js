// app/assets/javascripts/interview.js
var _interviewPortalInitialized = false;
function initInterviewPortal() {
  if (_interviewPortalInitialized) return;

  function byId(id) { return document.getElementById(id); }

  // Step elements
  const steps = document.querySelectorAll('.step');
  const stepIndicators = document.querySelectorAll('.step-indicator__item');
  if (!steps.length) return;

  _interviewPortalInitialized = true;

  // Step 1 elements
  const startBtn = byId('start_interview');
  const resumeBtn = byId('resume_interview');
  if (!startBtn) return;

  // Step 2 elements
  const statusEl = byId('interview_status');
  const progressBar = byId('progress_bar');
  const progressText = byId('progress_text');
  const questionCount = byId('question_count');
  const questionText = byId('question_text');
  const questionAudio = byId('question_audio');
  const mcqOptions = byId('mcq_options');
  const recordStart = byId('record_start');
  const recordStop = byId('record_stop');
  const recordStatus = byId('record_status');
  const recordedAudio = byId('recorded_audio');
  const submitBtn = byId('submit_answer');
  const completeBtn = byId('complete_interview');

  // Step 3 elements
  const resultStatus = byId('result_status');
  const resultFinal = byId('result_final_status');
  const resultAvg = byId('result_avg_score');
  const resultQs = byId('result_qs');
  const resultSummary = byId('result_summary');
  const resultStrengths = byId('result_strengths');
  const resultWeaknesses = byId('result_weaknesses');
  const resultRecommendation = byId('result_recommendation');
  const backToStartBtn = byId('back_to_start');

  let interviewId = null;
  let accessToken = null;
  let currentQuestion = null;
  let mediaRecorder = null;
  let recordedChunks = [];
  let recordedBlob = null;
  let selectedOption = null;
  let isSubmitting = false;

  // ===== API通信ヘルパー =====
  function authHeaders(extra) {
    var headers = extra || {};
    if (accessToken) headers['X-Interview-Token'] = accessToken;
    return headers;
  }

  async function apiRequest(url, options) {
    options = options || {};
    options.headers = authHeaders(options.headers || {});

    var res;
    try {
      res = await fetch(url, options);
    } catch (netErr) {
      throw new Error('\u30CD\u30C3\u30C8\u30EF\u30FC\u30AF\u30A8\u30E9\u30FC: ' + netErr.message);
    }

    var contentType = res.headers.get('content-type') || '';
    var data;
    if (contentType.indexOf('application/json') !== -1) {
      try {
        data = await res.json();
      } catch (e) {
        throw new Error('\u30B5\u30FC\u30D0\u30FC\u5FDC\u7B54\u306E\u89E3\u6790\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
      }
    } else {
      data = { success: false, error: '\u30B5\u30FC\u30D0\u30FC\u30A8\u30E9\u30FC (' + res.status + ')' };
    }

    if (res.status === 410 && data.reason === 'timeout') {
      data.__timeout = true;
    }
    if (res.status === 401) {
      data.__unauthorized = true;
    }

    if (data.__timeout || data.__unauthorized) {
      clearSavedInterview();
    }

    return { status: res.status, ok: res.ok, data: data };
  }

  // ===== ステップ制御 =====
  function showStep(n) {
    steps.forEach(function(s) { s.classList.remove('active'); });
    stepIndicators.forEach(function(item) { item.classList.remove('active', 'done'); });

    var target = byId('step-' + n);
    if (target) target.classList.add('active');

    stepIndicators.forEach(function(item) {
      var stepNum = parseInt(item.getAttribute('data-step'), 10);
      if (stepNum < n) item.classList.add('done');
      if (stepNum === n) item.classList.add('active');
    });
  }

  // ===== ステータス表示 =====
  function setStatus(msg) {
    if (statusEl) statusEl.textContent = msg;
  }

  function setProgress(progress, answered, total) {
    var pct = Math.max(0, Math.min(100, progress || 0));
    if (progressBar) progressBar.style.width = pct + '%';
    if (progressText) progressText.textContent = Math.round(pct) + '%';
    if (questionCount) questionCount.textContent = (answered || 0) + ' / ' + (total || 0) + ' \u554F';
  }

  // ===== localStorage =====
  function saveInterview(id, language) {
    localStorage.setItem('aiInterviewId', String(id));
    localStorage.setItem('aiInterviewLanguage', String(language || 'ja'));
  }

  function loadSavedInterview() {
    var id = localStorage.getItem('aiInterviewId');
    return id ? parseInt(id, 10) : null;
  }

  function clearSavedInterview() {
    localStorage.removeItem('aiInterviewId');
    localStorage.removeItem('aiInterviewLanguage');
    localStorage.removeItem('aiInterviewToken');
    accessToken = null;
  }

  // ===== API calls =====
  async function startInterview() {
    var situationId = byId('situation_id').value;
    var language = byId('language').value || 'ja';

    if (!situationId) {
      alert('\u9762\u63A5\u30D5\u30A9\u30FC\u30E0\u3092\u9078\u629E\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
      return;
    }

    startBtn.disabled = true;
    startBtn.textContent = '\u958B\u59CB\u4E2D...';

    try {
      var result = await apiRequest('/api/interviews/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ situation_id: parseInt(situationId, 10), language: language })
      });
      var data = result.data;

      if (data.__timeout || data.__unauthorized) {
        alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
        showStep(1);
        startBtn.disabled = false;
        startBtn.textContent = '\u9762\u63A5\u3092\u958B\u59CB\u3059\u308B';
        return;
      }

      if (!data.success) {
        alert(data.error || '\u9762\u63A5\u306E\u958B\u59CB\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
        startBtn.disabled = false;
        startBtn.textContent = '\u9762\u63A5\u3092\u958B\u59CB\u3059\u308B';
        return;
      }

      interviewId = data.interview_id;
      accessToken = data.access_token;
      saveInterview(interviewId, data.language);
      if (accessToken) localStorage.setItem('aiInterviewToken', accessToken);
      setStatus('\u9762\u63A5\u958B\u59CB');
      showStep(2);
      await loadNextQuestion();
    } catch (e) {
      alert('\u30A8\u30E9\u30FC: ' + e.message);
      startBtn.disabled = false;
      startBtn.textContent = '\u9762\u63A5\u3092\u958B\u59CB\u3059\u308B';
    }
  }

  async function resumeInterview() {
    var savedId = loadSavedInterview();
    if (!savedId) {
      alert('\u4FDD\u5B58\u3055\u308C\u305F\u9762\u63A5\u304C\u898B\u3064\u304B\u308A\u307E\u305B\u3093\u3002');
      return;
    }
    interviewId = savedId;
    accessToken = localStorage.getItem('aiInterviewToken');
    showStep(2);
    setStatus('\u9762\u63A5\u3092\u518D\u958B\u4E2D...');

    try {
      // まずステータスを確認
      var statusResult = await apiRequest('/api/interviews/' + interviewId + '/status', {});
      var statusData = statusResult.data;

      if (statusData.__timeout || statusData.__unauthorized) {
        alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
        showStep(1);
        return;
      }

      if (!statusData.success) {
        alert(statusData.error || '\u9762\u63A5\u306E\u53D6\u5F97\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
        clearSavedInterview();
        showStep(1);
        return;
      }

      var currentStatus = statusData.state && statusData.state.status;

      // 完了/失敗済みの場合は再開不可
      if (currentStatus === 'completed' || currentStatus === 'failed') {
        alert('\u3053\u306E\u9762\u63A5\u306F\u65E2\u306B\u5B8C\u4E86\u3057\u3066\u3044\u307E\u3059\u3002');
        clearSavedInterview();
        showStep(1);
        return;
      }

      if (currentStatus === 'not_started') {
        alert('\u9762\u63A5\u304C\u307E\u3060\u958B\u59CB\u3055\u308C\u3066\u3044\u307E\u305B\u3093\u3002');
        clearSavedInterview();
        showStep(1);
        return;
      }

      // abandonedまたはタイムアウト済みの場合は/resumeを呼んでin_progressに戻す
      if (currentStatus === 'abandoned') {
        var resumeResult = await apiRequest('/api/interviews/' + interviewId + '/resume', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' }
        });
        var resumeData = resumeResult.data;
        if (resumeData.__timeout || resumeData.__unauthorized) {
          alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
          showStep(1);
          return;
        }
        if (!resumeData.success) {
          alert(resumeData.error || '\u9762\u63A5\u306E\u518D\u958B\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
          clearSavedInterview();
          showStep(1);
          return;
        }
      }

      await refreshStatus();
      await loadNextQuestion();
    } catch (e) {
      alert('\u30A8\u30E9\u30FC: ' + e.message);
      clearSavedInterview();
      showStep(1);
    }
  }

  // 面接が途中で終了（failed / completed）した場合に結果画面へ自動遷移する。
  // /next_question が "Interview not in progress" を返した際の救済処理として使う。
  async function transitionIfInterviewEnded() {
    try {
      var result = await apiRequest('/api/interviews/' + interviewId + '/status', {});
      var data = result.data;
      if (!data || !data.success || !data.state) return false;

      var s = data.state.status;
      if (s === 'failed' || s === 'completed') {
        clearSavedInterview();

        // 結果画面を表示
        showStep(3);

        // 結果データを表示（complete APIのレスポンス互換の形で整形）
        var rejectionMsg = data.state.rejection_reason || '';
        displayResults({
          message: s === 'failed'
            ? '\u9762\u63A5\u304C\u7D42\u4E86\u3057\u307E\u3057\u305F\u3002' + (rejectionMsg ? ('\n' + rejectionMsg) : '')
            : '\u9762\u63A5\u304C\u5B8C\u4E86\u3057\u307E\u3057\u305F\u3002',
          result: {
            final_status: s === 'failed' ? 'failed' : 'passed',
            average_score: null,
            answered_questions: data.state.answered_questions,
            total_questions: data.state.total_questions
          }
        });
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  async function refreshStatus() {
    try {
      var result = await apiRequest('/api/interviews/' + interviewId + '/status', {});
      var data = result.data;
      if (data.__timeout || data.__unauthorized) {
        alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
        showStep(1);
        return;
      }
      if (!data.success) {
        setStatus(data.error || '\u30B9\u30C6\u30FC\u30BF\u30B9\u53D6\u5F97\u5931\u6557');
        return;
      }
      var state = data.state;
      setProgress(state.progress, state.answered_questions, state.total_questions);
    } catch (e) {
      setStatus('\u30B9\u30C6\u30FC\u30BF\u30B9\u53D6\u5F97\u5931\u6557');
    }
  }

  function renderOptions(options) {
    mcqOptions.innerHTML = '';
    selectedOption = null;
    if (!options || !options.choices) return;

    options.choices.forEach(function(choice) {
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'mcq-option';
      btn.textContent = choice;
      btn.addEventListener('click', function() {
        selectedOption = choice;
        document.querySelectorAll('.mcq-option').forEach(function(b) {
          b.classList.remove('selected');
        });
        btn.classList.add('selected');
      });
      mcqOptions.appendChild(btn);
    });
  }

  function animateQuestionTransition(callback) {
    var questionCard = questionText.closest('.interview-card');
    if (questionCard) {
      questionCard.classList.add('question-fade-out');
      setTimeout(function() {
        callback();
        questionCard.classList.remove('question-fade-out');
        questionCard.classList.add('question-fade-in');
        setTimeout(function() {
          questionCard.classList.remove('question-fade-in');
        }, 400);
        questionCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 250);
    } else {
      callback();
    }
  }

  async function loadNextQuestion() {
    try {
      var result = await apiRequest('/api/interviews/' + interviewId + '/next_question', {});
      var data = result.data;

      if (data.__timeout || data.__unauthorized) {
        alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
        showStep(1);
        return;
      }

      if (!data.success) {
        var transitioned = await transitionIfInterviewEnded();
        if (transitioned) return;

        setStatus(data.error || '\u8CEA\u554F\u306E\u53D6\u5F97\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
        return;
      }

      if (data.interview_complete) {
        setStatus('\u5168\u3066\u306E\u8CEA\u554F\u306B\u56DE\u7B54\u3057\u307E\u3057\u305F\u3002');
        questionText.textContent = '\u5168\u3066\u306E\u8CEA\u554F\u306B\u56DE\u7B54\u6E08\u307F\u3067\u3059\u3002\u300C\u9762\u63A5\u3092\u5B8C\u4E86\u3059\u308B\u300D\u3092\u30AF\u30EA\u30C3\u30AF\u3057\u3066\u304F\u3060\u3055\u3044\u3002';
        submitBtn.style.display = 'none';
        completeBtn.style.display = 'inline-block';
        return;
      }

      currentQuestion = data.question;

      animateQuestionTransition(function() {
        questionText.textContent = currentQuestion.question_text;

        if (currentQuestion.audio_url) {
          questionAudio.src = currentQuestion.audio_url;
          questionAudio.style.display = 'block';
        } else {
          questionAudio.style.display = 'none';
        }

        if (currentQuestion.options) {
          renderOptions(currentQuestion.options);
        } else {
          mcqOptions.innerHTML = '';
        }
      });

      submitBtn.style.display = 'inline-block';
      completeBtn.style.display = 'none';
      await refreshStatus();
      setStatus('\u8CEA\u554F\u3092\u8868\u793A\u4E2D');
    } catch (e) {
      setStatus('\u30A8\u30E9\u30FC: ' + e.message);
    }
  }

  async function submitAnswer() {
    if (isSubmitting) return;
    if (!currentQuestion) {
      alert('\u56DE\u7B54\u3059\u308B\u8CEA\u554F\u304C\u3042\u308A\u307E\u305B\u3093\u3002');
      return;
    }

    var textAnswer = byId('text_answer').value;
    var audioFileInput = byId('audio_file');
    var videoFileInput = byId('video_file');

    // Validate at least one answer
    var hasText = textAnswer && textAnswer.trim().length > 0;
    var hasAudio = audioFileInput.files[0];
    var hasVideo = videoFileInput.files[0];
    var hasRecording = recordedBlob !== null && recordedBlob.size > 0;
    var hasSelection = selectedOption;

    if (!hasText && !hasAudio && !hasVideo && !hasRecording && !hasSelection) {
      alert('\u56DE\u7B54\u3092\u5165\u529B\u3057\u3066\u304F\u3060\u3055\u3044\u3002\u30C6\u30AD\u30B9\u30C8\u3001\u97F3\u58F0\u3001\u307E\u305F\u306F\u9078\u629E\u80A2\u306E\u3044\u305A\u308C\u304B\u3092\u5165\u529B\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
      return;
    }

    isSubmitting = true;
    submitBtn.disabled = true;
    submitBtn.textContent = '\u9001\u4FE1\u4E2D...';

    var form = new FormData();
    form.append('question_id', currentQuestion.question_id);

    if (hasSelection) {
      form.append('selected_option', selectedOption);
    }

    if (hasText) {
      form.append('text_answer', textAnswer);
    }

    if (hasAudio) {
      form.append('audio_file', audioFileInput.files[0]);
    } else if (hasRecording) {
      form.append('audio_file', recordedBlob, 'recording.webm');
    }

    if (hasVideo) {
      form.append('video_file', videoFileInput.files[0]);
    }

    try {
      var result = await apiRequest('/api/interviews/' + interviewId + '/submit_answer', {
        method: 'POST',
        body: form
      });
      var data = result.data;

      if (data.__timeout || data.__unauthorized) {
        alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
        showStep(1);
        return;
      }

      if (!data.success) {
        alert(data.error || '\u56DE\u7B54\u306E\u9001\u4FE1\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
        return;
      }

      // Reset form
      recordedChunks = [];
      recordedBlob = null;
      selectedOption = null;
      if (recordedAudio) recordedAudio.src = '';
      if (recordStatus) recordStatus.textContent = '\u5F85\u6A5F\u4E2D';
      byId('text_answer').value = '';
      audioFileInput.value = '';
      videoFileInput.value = '';

      setStatus('\u56DE\u7B54\u3092\u9001\u4FE1\u3057\u307E\u3057\u305F\u3002\u6B21\u306E\u8CEA\u554F\u3092\u8AAD\u307F\u8FBC\u307F\u4E2D...');
      await loadNextQuestion();
    } catch (e) {
      alert('\u30A8\u30E9\u30FC: ' + e.message);
    } finally {
      isSubmitting = false;
      submitBtn.disabled = false;
      submitBtn.textContent = '\u56DE\u7B54\u3092\u9001\u4FE1';
    }
  }

  async function completeInterview() {
    completeBtn.disabled = true;
    completeBtn.textContent = '\u5B8C\u4E86\u51E6\u7406\u4E2D...';

    try {
      var result = await apiRequest('/api/interviews/' + interviewId + '/complete', {
        method: 'POST'
      });
      var data = result.data;

      if (data.__timeout || data.__unauthorized) {
        alert('\u30BB\u30C3\u30B7\u30E7\u30F3\u304C\u30BF\u30A4\u30E0\u30A2\u30A6\u30C8\u3057\u307E\u3057\u305F\u3002\u6700\u521D\u304B\u3089\u3084\u308A\u76F4\u3057\u3066\u304F\u3060\u3055\u3044\u3002');
        showStep(1);
        completeBtn.disabled = false;
        completeBtn.textContent = '\u9762\u63A5\u3092\u5B8C\u4E86\u3059\u308B';
        return;
      }

      if (!data.success) {
        alert(data.error || '\u9762\u63A5\u306E\u5B8C\u4E86\u306B\u5931\u6557\u3057\u307E\u3057\u305F\u3002');
        completeBtn.disabled = false;
        completeBtn.textContent = '\u9762\u63A5\u3092\u5B8C\u4E86\u3059\u308B';
        return;
      }

      clearSavedInterview();
      showStep(3);
      displayResults(data);
    } catch (e) {
      alert('\u30A8\u30E9\u30FC: ' + e.message);
      completeBtn.disabled = false;
      completeBtn.textContent = '\u9762\u63A5\u3092\u5B8C\u4E86\u3059\u308B';
    }
  }

  function displayResults(data) {
    var result = data.result || {};

    resultStatus.textContent = data.message || '\u9762\u63A5\u304C\u5B8C\u4E86\u3057\u307E\u3057\u305F\u3002';

    // Status badge styling
    var finalStatus = result.final_status || '-';
    resultFinal.textContent = finalStatus === 'passed' ? '\u5408\u683C' : finalStatus === 'failed' ? '\u4E0D\u5408\u683C' : finalStatus;
    resultFinal.className = 'result-item__value result-status--' + finalStatus;

    var avgScore = result.average_score;
    resultAvg.textContent = avgScore != null ? avgScore.toFixed(1) + ' / 100' : '-';

    resultQs.textContent = (result.answered_questions || 0) + ' / ' + (result.total_questions || 0) + ' \u554F';

    // Detailed results from status endpoint
    fetchDetailedResults();
  }

  async function fetchDetailedResults() {
    try {
      var result = await apiRequest('/api/interviews/' + interviewId + '/status', {});
      var data = result.data;
      if (!data.success || !data.state) return;

      var state = data.state;

      if (state.summary) {
        resultSummary.textContent = state.summary;
      }

      if (state.strengths && Array.isArray(state.strengths)) {
        resultStrengths.innerHTML = '';
        state.strengths.forEach(function(s) {
          var li = document.createElement('li');
          li.textContent = s;
          resultStrengths.appendChild(li);
        });
      }

      if (state.weaknesses && Array.isArray(state.weaknesses)) {
        resultWeaknesses.innerHTML = '';
        state.weaknesses.forEach(function(w) {
          var li = document.createElement('li');
          li.textContent = w;
          resultWeaknesses.appendChild(li);
        });
      }

      if (state.recommendation) {
        resultRecommendation.textContent = state.recommendation;
      }
    } catch (e) {
      // Detailed results not available
    }
  }

  // ===== 録音機能 =====
  async function setupRecorder() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      recordStatus.textContent = '\u3053\u306E\u30D6\u30E9\u30A6\u30B6\u3067\u306F\u9332\u97F3\u304C\u30B5\u30DD\u30FC\u30C8\u3055\u308C\u3066\u3044\u307E\u305B\u3093\u3002';
      return;
    }

    try {
      var stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaRecorder = new MediaRecorder(stream);

      mediaRecorder.ondataavailable = function(e) {
        if (e.data.size > 0) recordedChunks.push(e.data);
      };

      mediaRecorder.onstop = function() {
        if (recordedChunks.length === 0) {
          recordedBlob = null;
          recordStatus.textContent = '\u9332\u97F3\u30C7\u30FC\u30BF\u304C\u53D6\u5F97\u3067\u304D\u307E\u305B\u3093\u3067\u3057\u305F\u3002\u518D\u8A66\u884C\u3057\u3066\u304F\u3060\u3055\u3044\u3002';
          return;
        }
        var blob = new Blob(recordedChunks, { type: 'audio/webm' });
        recordedBlob = blob;
        if (recordedAudio.src && recordedAudio.src.indexOf('blob:') === 0) {
          URL.revokeObjectURL(recordedAudio.src);
        }
        recordedAudio.src = URL.createObjectURL(blob);
        recordStatus.textContent = '\u9332\u97F3\u5B8C\u4E86';
      };
    } catch (e) {
      recordStatus.textContent = '\u30DE\u30A4\u30AF\u306E\u4F7F\u7528\u304C\u8A31\u53EF\u3055\u308C\u3066\u3044\u307E\u305B\u3093\u3002';
      mediaRecorder = null;
    }
  }

  // ===== Event listeners =====
  startBtn.addEventListener('click', startInterview);
  if (resumeBtn) resumeBtn.addEventListener('click', resumeInterview);
  if (submitBtn) submitBtn.addEventListener('click', submitAnswer);
  if (completeBtn) completeBtn.addEventListener('click', completeInterview);

  if (recordStart) {
    recordStart.addEventListener('click', async function() {
      if (!mediaRecorder) await setupRecorder();
      if (!mediaRecorder) return;
      recordedChunks = [];
      recordedBlob = null;
      if (recordedAudio && recordedAudio.src && recordedAudio.src.indexOf('blob:') === 0) {
        URL.revokeObjectURL(recordedAudio.src);
      }
      if (recordedAudio) recordedAudio.src = '';
      mediaRecorder.start();
      recordStart.disabled = true;
      recordStop.disabled = false;
      recordStatus.textContent = '\u9332\u97F3\u4E2D...';
    });
  }

  if (recordStop) {
    recordStop.addEventListener('click', function() {
      if (!mediaRecorder) return;
      mediaRecorder.stop();
      recordStart.disabled = false;
      recordStop.disabled = true;
    });
  }

  if (backToStartBtn) {
    backToStartBtn.addEventListener('click', function() {
      showStep(1);
      startBtn.disabled = false;
      startBtn.textContent = '\u9762\u63A5\u3092\u958B\u59CB\u3059\u308B';
    });
  }

  // Check for saved interview
  var savedId = loadSavedInterview();
  if (resumeBtn) resumeBtn.disabled = !savedId;
}

document.addEventListener('turbolinks:load', initInterviewPortal);
document.addEventListener('turbolinks:before-visit', function() {
  _interviewPortalInitialized = false;
});
