;; StarterLaunch: Decentralized Startup Incubator (Stage 3)
;; Added milestone progression and funding release mechanism

(define-constant CONTRACT_OWNER tx-sender)
(define-constant MAX_MILESTONE_FUNDING u50000)

;; [Previous Stage 2 code remains the same, with following additions]

(define-public (submit-milestone-completion 
    (startup-id uint)
    (milestone-id uint)
    (completion-report (string-ascii 500)))
    
    (let (
        (startup (unwrap! (map-get? Startups {startup-id: startup-id}) (err u301)))
        (milestone (unwrap! (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id}) (err u302)))
    )
        (asserts! (is-eq tx-sender (get founder startup)) (err u303))
        (asserts! (is-eq (get status milestone) "PENDING") (err u304))
        
        (map-set Milestones
            { startup-id: startup-id, milestone-id: milestone-id }
            (merge milestone 
                {
                    status: "COMPLETED",
                    completion-report: (some completion-report)
                }
            )
        )
        (ok true)
    )
)

(define-public (approve-milestone-funding 
    (startup-id uint)
    (milestone-id uint))
    
    (let (
        (startup (unwrap! (map-get? Startups {startup-id: startup-id}) (err u305)))
        (milestone (unwrap! (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id}) (err u306)))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) (err u307))
        (asserts! (is-eq (get status milestone) "COMPLETED") (err u308))
        (asserts! (<= (get funding milestone) MAX_MILESTONE_FUNDING) (err u309))
        
        ;; Release funds to startup founder
        (try! (as-contract (stx-transfer? (get funding milestone) tx-sender (get founder startup))))
        
        (map-set Milestones
            { startup-id: startup-id, milestone-id: milestone-id }
            (merge milestone { status: "FUNDED" })
        )
        
        (ok true)
    )
)

(define-read-only (get-milestone-status 
    (startup-id uint)
    (milestone-id uint))
    
    (map-get? Milestones {startup-id: startup-id, milestone-id: milestone-id})
)