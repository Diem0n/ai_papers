//
//  RouteTrainingData.swift
//  AIPapers
//
//  Labeled example messages for the query router: is the user asking to
//  *learn a concept* (explain) or asking about *their saved papers* (archive)?
//  Small on purpose — the classifier is a linear model on word features, and
//  this list is the only thing to edit when it routes something wrongly.
//

import Foundation

nonisolated enum RouteTrainingData {
    static let explain: [String] = [
        "what is a kv cache", "explain reciprocal rank fusion", "how does attention work",
        "difference between lora and qlora", "teach me about rlhf", "eli5 speculative decoding",
        "why does batch norm help training", "intuition for cosine similarity", "kv cache",
        "mixture of experts", "flash attention", "what are embeddings", "how do transformers work",
        "explain backpropagation", "what does temperature do in sampling", "what is quantization",
        "help me understand rotary position embeddings", "explain like i'm five what a diffusion model is",
        "how does retrieval augmented generation work", "why do llms hallucinate",
        "what is the difference between precision and recall", "explain the bias variance tradeoff",
        "how does a vector database index work", "what is chain of thought prompting",
        "walk me through how gradient descent works", "what's a token in a language model",
        "explain grouped query attention", "how does fine tuning differ from pretraining",
        "what is direct preference optimization", "tell me about mixture of depths",
        "what is perplexity", "how does beam search work", "explain contrastive learning",
        "what is a reward model", "teach me how paged attention works", "why is softmax used",
        "define overfitting", "explain kl divergence", "how does speculative decoding speed things up",
        "what is a lora adapter", "intuition behind layer normalization", "what is model distillation",
        "how do agents use tools", "what is in context learning", "explain the react pattern",
        "how does bm25 work", "what is a knowledge graph", "explain tf idf", "what is self attention",
        "why does dropout work", "how does prompt caching work", "what is a context window",
        "explain continuous batching", "what is rag", "how does tokenization work",
        "what's the idea behind reinforcement learning from human feedback", "explain mixture of agents",
        "what is retrieval", "give me an intuition for transformers", "how does int8 quantization work",
    ]

    static let archive: [String] = [
        "what's new in agents", "which papers cover kv cache", "summarize what i saved about rag",
        "papers on retrieval from this week", "have i read anything on diffusion",
        "show my favorites about agents", "what did i save on evaluation", "which of my papers mention lora",
        "latest papers on inference", "any new papers about reasoning", "what's new in rag",
        "what papers do i have on quantization", "find papers about speculative decoding",
        "which papers talk about mixture of experts", "what did i read last week",
        "recent papers on multimodal models", "list my unread papers on agents",
        "what are the newest papers in my archive", "do i have anything about long context",
        "which paper proposed the best benchmark for agents", "summarize this week's papers",
        "what's trending in my archive", "papers about fine tuning i haven't read",
        "any papers on hallucination", "show papers related to retrieval", "what's new this week",
        "which saved papers use reinforcement learning", "papers that mention lora and quantization",
        "what have i saved on evaluation", "which papers should i read next", "what's new in inference",
        "did i save anything on vision language models", "recent work on tool use in my papers",
        "compare the papers i saved on rag", "what do my papers say about kv cache",
        "top papers on reasoning in my archive", "what papers came in today", "new papers about training",
        "which papers in my library cover agents security", "what's the latest on diffusion",
        "any new papers on distillation", "what did the papers i read say about scaling",
        "papers on mlops", "show me recent papers about multi agent systems",
        "what are the key papers on retrieval in my archive", "which papers have code available",
        "what's new in evaluation", "which papers are about fine tuning", "papers i favorited on agents",
        "which papers discuss prompt injection", "what's in my archive about embeddings",
        "recent papers on efficient inference", "how many papers do i have on rag",
        "find papers similar to the one i just read", "what new papers are about reward models",
        "which papers mention benchmarks for coding agents", "what's new in classical ml",
        "which papers touch on tokenization", "any recent papers on context windows",
        "what did i save about chain of thought", "papers this month on reasoning",
    ]

    /// Held out from training — used only to measure the router.
    static let heldOutExplain: [String] = [
        "what is a transformer", "explain low rank adaptation", "how does a learning rate schedule work",
        "difference between rag and fine tuning", "what's a vector embedding", "teach me about attention heads",
        "why does gradient clipping help", "explain word2vec", "eli5 reinforcement learning",
        "how does a diffusion model generate images", "what is the softmax temperature",
        "explain mixture of experts routing", "cross entropy loss", "what is a mask in attention",
        "how does prefix caching work",
    ]

    static let heldOutArchive: [String] = [
        "what's new in reasoning", "which papers do i have on agents", "any recent papers about rag",
        "what did i save about fine tuning", "papers on inference from this week",
        "show my saved papers on diffusion", "which of my papers cover evaluation", "what's the latest in my archive",
        "have i saved anything about lora", "new papers on multimodal today", "which papers mention kv cache",
        "what are my unread papers about retrieval", "recent papers about quantization",
        "list papers on tool use", "what came in this week on training",
    ]
}
