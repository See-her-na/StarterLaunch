;; StarterLaunch: Decentralized Startup Incubator (Stage 2)
;; Added investment and startup evaluation mechanisms

(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_FUNDING u1000)
(define-constant MAX_FUNDING u1000000)
(define-constant MAX_MILESTONES u5)
(define-constant MINIMUM_INVESTMENT u100)
(define-constant APPROVAL_THRESHOLD u500)

(define-map Startups 
    { startup-id: uint }
    {
        founder: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        total-funding: uint,
        milestone-count: uint,
        total-invested: uint,
        total-positive-votes: uint,
        total-negative-votes: uint,
        status: (string-ascii 20)
    }
)

(define-map Milestones
    { startup-id: uint, milestone-id: uint }
    {
        description: (string-ascii 200),
        funding: uint,
        status: (string-ascii 20)
    }
)

(define-map Investments
    { startup-id: uint, investor: principal }
    {
        amount: uint,
        supports: bool
    }
)

(define-data-var startup-counter uint u0)

;; [Previous Stage 1 functions remain the same]

(define-public (invest-in-startup 
    (startup-id uint) 
    (amount uint)
    (supports bool))
    
    (let ((startup (unwrap! (map-get? Startups {startup-id: startup-id}) (err u201))))
        (asserts! (>= amount MINIMUM_INVESTMENT) (err u202))
        
        ;; Prevent duplicate investments
        (asserts! (is-none (map-get? Investments {startup-id: startup-id, investor: tx-sender})) (err u203))
        
        ;; Transfer investment
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Record investment
        (map-set Investments 
            { startup-id: startup-id, investor: tx-sender }
            { 
                amount: amount, 
                supports: supports 
            }
        )
        
        ;; Update startup voting metrics
        (let ((updated-startup 
            (merge startup 
                {
                    total-invested: (+ (get total-invested startup) amount),
                    total-positive-votes: (if supports 
                        (+ (get total-positive-votes startup) amount)
                        (get total-positive-votes startup)
                    ),
                    total-negative-votes: (if (not supports)
                        (+ (get total-negative-votes startup) amount)
                        (get total-negative-votes startup)
                    )
                }
            )))
            
            (map-set Startups 
                { startup-id: startup-id }
                updated-startup
            )
            
            (ok true)
        )
    )
)

(define-read-only (get-startup-status (startup-id uint))
    (let ((startup (unwrap! (map-get? Startups {startup-id: startup-id}) (err u204))))
        (let ((total-votes (+ (get total-positive-votes startup) (get total-negative-votes startup))))
            (if (> total-votes u0)
                (if (>= 
                    (* (get total-positive-votes startup) u1000) 
                    (* total-votes APPROVAL_THRESHOLD)
                )
                    (ok "APPROVED")
                    (ok "REJECTED")
                )
                (ok "PENDING")
            )
        )
    )
)