import Foundation

/// A starting structure for a new project. Stage deadlines are stored as a
/// position between 0 (start date) and 1 (final deadline) so any template can
/// be stretched over the dates the user actually has.
struct ProjectTemplate: Identifiable, Hashable {
    struct Stage: Hashable {
        let title: String
        let position: Double
        let tasks: [String]
    }

    let id: String
    let name: String
    let summary: String
    let stages: [Stage]

    /// Concrete stages with deadlines spread between `start` and `end`.
    func makeStages(start: Date, end: Date) -> [ProjectStage] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = max(cal.startOfDay(for: end), startDay)
        let span = endDay.timeIntervalSince(startDay)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return stages.map { stage in
            let date = startDay.addingTimeInterval(span * min(max(stage.position, 0), 1))
            return ProjectStage(title: stage.title,
                                weight: nil,
                                deadline: f.string(from: cal.startOfDay(for: date)),
                                tasks: stage.tasks.map { ProjectTask(title: $0) })
        }
    }

    static var `default`: ProjectTemplate { all[0] }

    static let all: [ProjectTemplate] = [
        ProjectTemplate(
            id: "final-year-project",
            name: "Final-year project",
            summary: "Undergraduate capstone: proposal, literature, build, evaluation, report, demo.",
            stages: [
                Stage(title: "Proposal & Scope", position: 0.10, tasks: [
                    "Define your topic, problem statement, and objectives",
                    "Agree scope and success criteria with your supervisor",
                    "Write and submit the proposal"]),
                Stage(title: "Literature Review", position: 0.25, tasks: [
                    "Collect and read the key papers in your area",
                    "Summarise findings in a review matrix",
                    "Identify and articulate your research gap"]),
                Stage(title: "Requirements & Design", position: 0.40, tasks: [
                    "Write the functional and non-functional requirements",
                    "Draft the architecture or study design",
                    "Get the design signed off"]),
                Stage(title: "Implementation", position: 0.62, tasks: [
                    "Build the core of the project",
                    "Keep a log of key decisions and issues",
                    "Check in with your supervisor on progress"]),
                Stage(title: "Testing & Evaluation", position: 0.78, tasks: [
                    "Run the evaluation with proper metrics",
                    "Compare against a baseline where possible",
                    "Write up results honestly, including limitations"]),
                Stage(title: "Report Draft", position: 0.90, tasks: [
                    "Assemble all chapters into one draft",
                    "Consistency and referencing pass",
                    "Revise after supervisor feedback"]),
                Stage(title: "Final Submission & Demo", position: 1.0, tasks: [
                    "Proofread, format, and check references",
                    "Prepare and rehearse the demonstration",
                    "Back up in two places, then submit"]),
            ]),
        ProjectTemplate(
            id: "masters-dissertation",
            name: "Master's dissertation",
            summary: "Topic and proposal through methodology, data, analysis and the final write-up.",
            stages: [
                Stage(title: "Topic & Proposal", position: 0.12, tasks: [
                    "Agree the research question with your supervisor",
                    "Write the proposal and timeline",
                    "Submit the proposal form"]),
                Stage(title: "Literature Review", position: 0.30, tasks: [
                    "Read and log the core papers",
                    "Build the literature review matrix",
                    "Write the review chapter draft"]),
                Stage(title: "Methodology & Ethics", position: 0.42, tasks: [
                    "Choose methods and justify them",
                    "Complete the ethics application",
                    "Draft the methodology chapter"]),
                Stage(title: "Data Collection", position: 0.62, tasks: [
                    "Collect or generate the data",
                    "Clean and document the dataset",
                    "Back up the raw data"]),
                Stage(title: "Analysis & Results", position: 0.78, tasks: [
                    "Run the analysis",
                    "Produce figures and tables",
                    "Write the results chapter"]),
                Stage(title: "Full Draft", position: 0.90, tasks: [
                    "Write discussion and conclusion",
                    "Full supervisor review round",
                    "Revise per feedback"]),
                Stage(title: "Final Submission", position: 1.0, tasks: [
                    "Final proofreading and formatting",
                    "Check every reference and appendix",
                    "Submit and keep the receipt"]),
            ]),
        ProjectTemplate(
            id: "phd-year",
            name: "PhD year plan",
            summary: "One research year: study design, data, analysis, a paper and the annual review.",
            stages: [
                Stage(title: "Literature Update", position: 0.15, tasks: [
                    "Update the review with the latest papers",
                    "Refine the research questions"]),
                Stage(title: "Study Design & Ethics", position: 0.30, tasks: [
                    "Finalise the study design",
                    "Obtain ethics approval"]),
                Stage(title: "Data Collection", position: 0.55, tasks: [
                    "Run the study or experiments",
                    "Document procedures and deviations"]),
                Stage(title: "Analysis", position: 0.70, tasks: [
                    "Analyse the data",
                    "Discuss results with supervisors"]),
                Stage(title: "Paper Draft", position: 0.85, tasks: [
                    "Draft the paper",
                    "Circulate to co-authors"]),
                Stage(title: "Annual Review", position: 1.0, tasks: [
                    "Write the annual progress report",
                    "Prepare the review presentation"]),
            ]),
        ProjectTemplate(
            id: "certification",
            name: "Certification or exam",
            summary: "Syllabus plan, study blocks, practice exams, revision, exam day.",
            stages: [
                Stage(title: "Syllabus & Plan", position: 0.10, tasks: [
                    "List every syllabus topic",
                    "Book the exam date",
                    "Plan weekly study blocks"]),
                Stage(title: "Study Block 1", position: 0.35, tasks: [
                    "Work through the first half of the topics",
                    "Make summary notes"]),
                Stage(title: "Study Block 2", position: 0.60, tasks: [
                    "Work through the second half of the topics",
                    "Make summary notes"]),
                Stage(title: "Practice Exams", position: 0.80, tasks: [
                    "Sit two timed practice exams",
                    "Review every wrong answer"]),
                Stage(title: "Revision", position: 0.93, tasks: [
                    "Revise weak topics",
                    "Final read-through of notes"]),
                Stage(title: "Exam Day", position: 1.0, tasks: [
                    "Check the venue, ID and equipment",
                    "Sit the exam"]),
            ]),
        ProjectTemplate(
            id: "personal-project",
            name: "Personal project",
            summary: "Scope, plan, build, test, polish, launch. Good for a side project or portfolio piece.",
            stages: [
                Stage(title: "Define Scope", position: 0.10, tasks: [
                    "Write down what done looks like",
                    "List what is out of scope"]),
                Stage(title: "Plan & Design", position: 0.25, tasks: [
                    "Sketch the design",
                    "Break the work into pieces"]),
                Stage(title: "Build v1", position: 0.55, tasks: [
                    "Build the core",
                    "Keep notes on decisions"]),
                Stage(title: "Test & Feedback", position: 0.75, tasks: [
                    "Try it end to end",
                    "Get feedback from two people"]),
                Stage(title: "Polish", position: 0.90, tasks: [
                    "Fix what the feedback showed",
                    "Tidy the rough edges"]),
                Stage(title: "Launch", position: 1.0, tasks: [
                    "Publish or hand over",
                    "Write down what you'd do differently"]),
            ]),
        ProjectTemplate(
            id: "blank",
            name: "Start from scratch",
            summary: "A single placeholder stage. Add your own stages and tasks in the editor.",
            stages: [
                Stage(title: "First stage", position: 1.0, tasks: ["First task"]),
            ]),
    ]
}
