import { runAIEvaluationSuite } from '../evaluations/evaluator';

console.log('=============== DREAMING AGRI AI EVALUATION SUITE ===============');
const report = runAIEvaluationSuite();
console.log(`Timestamp: ${report.timestamp}`);
console.log(`Total Tests: ${report.total_tests}`);
console.log(`Passed Tests: ${report.passed_tests}`);
console.log(`Accuracy Rate: ${report.accuracy_rate}%`);
console.log(`Confidence Calibration Score: ${report.confidence_calibration_score}`);
console.log(`Disclaimer Compliance: ${report.disclaimer_compliance ? 'YES' : 'NO'}`);
console.log('-----------------------------------------------------------------');
report.details.forEach((d, i) => {
	console.log(`[Test ${i + 1}] ${d.module}: ${d.status} (Confidence: ${d.confidence})`);
	console.log(`         Detail: ${d.message}`);
});
console.log('=================================================================');
