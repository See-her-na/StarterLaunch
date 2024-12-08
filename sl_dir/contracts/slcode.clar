;; StarterLaunch: Decentralized Startup Incubator (Stage 1)
;; Basic startup submission and milestone tracking

(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_FUNDING u1000)
(define-constant MAX_FUNDING u1000000)
(define-constant MAX_MILESTONES u5)

(define-map Startups 
    { startup-id: uint }
    {
        founder: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        total-funding: uint,
        milestone-count: uint
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

(define-data-var startup-counter uint u0)

(define-public (submit-startup 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (total-funding uint)
    (milestone-count uint))
    
    (begin
        (asserts! (and (>= total-funding MIN_FUNDING) (<= total-funding MAX_FUNDING)) 
            (err u100))
        (asserts! (and (> milestone-count u0) (<= milestone-count MAX_MILESTONES))
            (err u101))
        
        (let ((new-startup-id (+ (var-get startup-counter) u1)))
            (map-set Startups 
                { startup-id: new-startup-id }
                {
                    founder: tx-sender,
                    title: title,
                    description: description,
                    total-funding: total-funding,
                    milestone-count: milestone-count
                }
            )
            (var-set startup-counter new-startup-id)
            (ok new-startup-id)
        )
    )
)

(define-public (add-milestone
    (startup-id uint)
    (milestone-id uint)
    (description (string-ascii 200))
    (funding uint))
    
    (let ((startup (unwrap! (map-get? Startups {startup-id: startup-id}) (err u102))))
        (asserts! (< milestone-id (get milestone-count startup)) (err u103))
        (asserts! (is-eq tx-sender (get founder startup)) (err u104))
        
        (map-set Milestones
            { startup-id: startup-id, milestone-id: milestone-id }
            {
                description: description,
                funding: funding,
                status: "PENDING"
            }
        )
        (ok true)
    )
)

(define-read-only (get-startup (startup-id uint))
    (map-get? Startups {startup-id: startup-id})
)

(define-read-only (get-milestone (startup-id uint) (milestone-id uint))
    (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id})
)