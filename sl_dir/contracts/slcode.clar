;; Decentralized Startup Incubator Platform (StarterLaunch)
;; A system for funding and supporting early-stage startups with milestone-based investments

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MINIMUM_INVESTMENT_AMOUNT u100)
(define-constant DUE_DILIGENCE_DURATION u1209600) ;; 14 days in seconds
(define-constant APPROVAL_THRESHOLD u500) ;; 50.0% represented as 500/1000
(define-constant MAX_INVESTMENT u1000000000) ;; Maximum investment allowed for startups
(define-constant MIN_TITLE_LENGTH u4)
(define-constant MIN_PITCH_LENGTH u10)

;; Error codes
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_STARTUP (err u101))
(define-constant ERR_ALREADY_EVALUATED (err u102))
(define-constant ERR_INSUFFICIENT_INVESTMENT (err u103))
(define-constant ERR_EVALUATION_CLOSED (err u104))
(define-constant ERR_MILESTONE_INVALID (err u105))
(define-constant ERR_STARTUP_NOT_APPROVED (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_INVALID_MILESTONE_COUNT (err u108))
(define-constant ERR_INVALID_TITLE (err u109))
(define-constant ERR_INVALID_PITCH (err u110))
(define-constant ERR_TIMESTAMP_ORACLE_MISSING (err u111))

;; Data Maps and Variables
(define-map Startups
    { startup-id: uint }
    {
        founder: principal,
        title: (string-ascii 100),
        pitch: (string-ascii 500),
        total-funding: uint,
        milestone-count: uint,
        current-milestone: uint,
        start-timestamp: uint,
        end-timestamp: uint,
        status: (string-ascii 20),
        total-positive-eval: uint,
        total-negative-eval: uint,
        total-eval-weight: uint
    }
)

(define-map Milestones
    { startup-id: uint, milestone-id: uint }
    {
        funding: uint,
        deliverables: (string-ascii 200),
        status: (string-ascii 20),
        progress-report: (optional (string-ascii 200))
    }
)

(define-map Evaluations
    { startup-id: uint, investor: principal }
    {
        amount: uint,
        support: bool,
        investment-amount: uint
    }
)

(define-map InvestorStakes
    { user: principal }
    { total-invested: uint }
)

(define-data-var startup-counter uint u0)
(define-data-var timestamp-oracle principal (default-to tx-sender (contract-call? .timestamp-contract get-oracle-address)))

;; Private functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (calculate-eval-weight (investment-amount uint))
    investment-amount
)

(define-private (is-valid-startup-id (startup-id uint))
    (<= startup-id (var-get startup-counter))
)

(define-private (is-valid-milestone-id (milestone-id uint) (milestone-count uint))
    (< milestone-id milestone-count)
)

(define-private (is-valid-amount (amount uint))
    (and (> amount u0) (<= amount MAX_INVESTMENT))
)

(define-private (is-valid-title (title (string-ascii 100)))
    (>= (len title) MIN_TITLE_LENGTH)
)

(define-private (is-valid-pitch (pitch (string-ascii 500)))
    (>= (len pitch) MIN_PITCH_LENGTH)
)

(define-private (get-current-timestamp)
    (contract-call? .timestamp-contract get-current-timestamp)
)

(define-private (validate-and-process-eval (support-vote bool) (eval-weight uint) (eval-data (tuple (total-positive-eval uint) (total-negative-eval uint) (total-eval-weight uint))))
    (let (
        (safe-support (validate-support-bool support-vote))
        (current-positive-eval (get total-positive-eval eval-data))
        (current-negative-eval (get total-negative-eval eval-data))
        (current-total-weight (get total-eval-weight eval-data))
    )
        {
            total-positive-eval: (if safe-support 
                (+ current-positive-eval eval-weight)
                current-positive-eval
            ),
            total-negative-eval: (if safe-support
                current-negative-eval
                (+ current-negative-eval eval-weight)
            ),
            total-eval-weight: (+ current-total-weight eval-weight)
        }
    )
)

(define-private (validate-support-bool (support-vote bool))
    (if support-vote true false)
)

(define-private (safe-merge-startup-evals (startup-map {
        founder: principal,
        title: (string-ascii 100),
        pitch: (string-ascii 500),
        total-funding: uint,
        milestone-count: uint,
        current-milestone: uint,
        start-timestamp: uint,
        end-timestamp: uint,
        status: (string-ascii 20),
        total-positive-eval: uint,
        total-negative-eval: uint,
        total-eval-weight: uint
    }) 
    (eval-updates {
        total-positive-eval: uint,
        total-negative-eval: uint,
        total-eval-weight: uint
    }))
    (merge startup-map
        {
            total-positive-eval: (get total-positive-eval eval-updates),
            total-negative-eval: (get total-negative-eval eval-updates),
            total-eval-weight: (get total-eval-weight eval-updates)
        }
    )
)

;; Public functions
(define-public (submit-startup (title (string-ascii 100)) 
                             (pitch (string-ascii 500)) 
                             (total-funding uint)
                             (milestone-count uint))
    (begin
        (asserts! (is-valid-title title) ERR_INVALID_TITLE)
        (asserts! (is-valid-pitch pitch) ERR_INVALID_PITCH)
        (asserts! (is-valid-amount total-funding) ERR_INVALID_AMOUNT)
        (asserts! (and (> milestone-count u0) (<= milestone-count u10)) ERR_INVALID_MILESTONE_COUNT)
        
        (let (
            (startup-id (+ (var-get startup-counter) u1))
            (current-timestamp (get-current-timestamp))
        )
            (map-set Startups
                { startup-id: startup-id }
                {
                    founder: tx-sender,
                    title: title,
                    pitch: pitch,
                    total-funding: total-funding,
                    milestone-count: milestone-count,
                    current-milestone: u0,
                    start-timestamp: current-timestamp,
                    end-timestamp: (+ current-timestamp DUE_DILIGENCE_DURATION),
                    status: "ACTIVE",
                    total-positive-eval: u0,
                    total-negative-eval: u0,
                    total-eval-weight: u0
                }
            )
            (var-set startup-counter startup-id)
            (ok startup-id)
        )
    )
)

(define-public (add-milestone (startup-id uint) 
                            (milestone-id uint)
                            (funding uint)
                            (deliverables (string-ascii 200)))
    (begin
        (asserts! (is-valid-pitch deliverables) ERR_INVALID_PITCH)
        (let ((startup (unwrap! (map-get? Startups {startup-id: startup-id}) ERR_INVALID_STARTUP)))
            (asserts! (is-valid-startup-id startup-id) ERR_INVALID_STARTUP)
            (asserts! (is-valid-amount funding) ERR_INVALID_AMOUNT)
            (asserts! (is-valid-milestone-id milestone-id (get milestone-count startup)) ERR_MILESTONE_INVALID)
            (asserts! (is-eq (get founder startup) tx-sender) ERR_NOT_AUTHORIZED)
            
            (map-set Milestones
                { startup-id: startup-id, milestone-id: milestone-id }
                {
                    funding: funding,
                    deliverables: deliverables,
                    status: "PENDING",
                    progress-report: none
                }
            )
            (ok true)
        )
    )
)

(define-public (evaluate-startup (startup-id uint) (support bool) (investment-amount uint))
    (let (
        (startup (unwrap! (map-get? Startups {startup-id: startup-id}) ERR_INVALID_STARTUP))
        (current-timestamp (get-current-timestamp))
        (eval-weight (calculate-eval-weight investment-amount))
        (safe-support (validate-support-bool support))
    )
        (asserts! (is-valid-startup-id startup-id) ERR_INVALID_STARTUP)
        (asserts! (>= investment-amount MINIMUM_INVESTMENT_AMOUNT) ERR_INSUFFICIENT_INVESTMENT)
        (asserts! (<= current-timestamp (get end-timestamp startup)) ERR_EVALUATION_CLOSED)
        (asserts! (is-none (map-get? Evaluations {startup-id: startup-id, investor: tx-sender})) ERR_ALREADY_EVALUATED)
        
        (try! (stx-transfer? investment-amount tx-sender (as-contract tx-sender)))
        
        (map-set Evaluations
            {startup-id: startup-id, investor: tx-sender}
            {
                amount: investment-amount,
                support: safe-support,
                investment-amount: investment-amount
            }
        )
        
        (let (
            (updated-evals (validate-and-process-eval 
                safe-support
                eval-weight
                {
                    total-positive-eval: (get total-positive-eval startup),
                    total-negative-eval: (get total-negative-eval startup),
                    total-eval-weight: (get total-eval-weight startup)
                }
            ))
        )
            (map-set Startups
                {startup-id: startup-id}
                (safe-merge-startup-evals startup updated-evals)
            )
            (ok true)
        )
    )
)

(define-public (submit-milestone-progress 
    (startup-id uint)
    (milestone-id uint)
    (report (string-ascii 200)))
    
    (let (
        (startup (unwrap! (map-get? Startups {startup-id: startup-id}) ERR_INVALID_STARTUP))
        (milestone (unwrap! (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id}) ERR_MILESTONE_INVALID))
    )
        (asserts! (is-valid-startup-id startup-id) ERR_INVALID_STARTUP)
        (asserts! (is-valid-milestone-id milestone-id (get milestone-count startup)) ERR_MILESTONE_INVALID)
        (asserts! (is-eq (get founder startup) tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq milestone-id (get current-milestone startup)) ERR_MILESTONE_INVALID)
        
        (map-set Milestones
            {startup-id: startup-id, milestone-id: milestone-id}
            (merge milestone
                {
                    status: "PENDING_REVIEW",
                    progress-report: (some report)
                }
            )
        )
        (ok true)
    )
)

(define-public (approve-milestone (startup-id uint) (milestone-id uint))
    (let (
        (startup (unwrap! (map-get? Startups {startup-id: startup-id}) ERR_INVALID_STARTUP))
        (milestone (unwrap! (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id}) ERR_MILESTONE_INVALID))
    )
        (asserts! (is-valid-startup-id startup-id) ERR_INVALID_STARTUP)
        (asserts! (is-valid-milestone-id milestone-id (get milestone-count startup)) ERR_MILESTONE_INVALID)
        (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
        
        (try! (as-contract (stx-transfer? (get funding milestone) tx-sender (get founder startup))))
        
        (map-set Milestones
            {startup-id: startup-id, milestone-id: milestone-id}
            (merge milestone {status: "COMPLETED"})
        )
        
        (map-set Startups
            {startup-id: startup-id}
            (merge startup
                {
                    current-milestone: (+ milestone-id u1),
                    status: (if (>= (+ milestone-id u1) (get milestone-count startup))
                        "COMPLETED"
                        "ACTIVE"
                    )
                }
            )
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-startup (startup-id uint))
    (map-get? Startups {startup-id: startup-id})
)

(define-read-only (get-milestone (startup-id uint) (milestone-id uint))
    (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id})
)

(define-read-only (get-evaluation (startup-id uint) (investor principal))
    (map-get? Evaluations {startup-id: startup-id, investor: investor})
)

(define-read-only (get-startup-result (startup-id uint))
    (let ((startup (unwrap! (map-get? Startups {startup-id: startup-id}) ERR_INVALID_STARTUP)))
        (asserts! (is-valid-startup-id startup-id) ERR_INVALID_STARTUP)
        (let ((current-timestamp (get-current-timestamp)))
            (if (>= current-timestamp (get end-timestamp startup))
                (let (
                    (total-evals (get total-eval-weight startup))
                    (positive-evals (get total-positive-eval startup))
                )
                    (if (and
                        (> total-evals u0)
                        (>= (* positive-evals u1000) (* total-evals APPROVAL_THRESHOLD))
                    )
                        (ok "APPROVED")
                        (ok "REJECTED")
                    )
                )
                (ok "EVALUATION_ACTIVE")
            )
        )
    )
)

;; Admin function to update timestamp oracle address
(define-public (set-timestamp-oracle (new-oracle principal))
    (begin
        (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
        (var-set timestamp-oracle new-oracle)
        (ok true)
    )
)