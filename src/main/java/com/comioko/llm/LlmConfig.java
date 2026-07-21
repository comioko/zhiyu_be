package com.comioko.llm;

import com.comioko.llm.service.KnowPostDescriptionService;
import com.comioko.llm.service.impl.KnowPostDescriptionServiceImpl;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * LLM 配置。
 *
 * 当 spring.ai.openai.api-key 有值时（即 AI 启用），注册 ChatClient 和 KnowPostDescriptionService。
 * 使用 {@code @ConditionalOnProperty} 而非 {@code @ConditionalOnBean}：
 * 1. 属性在 Spring Environment 阶段就解析，条件评估时机更早
 * 2. 避免 bean 之间循环依赖
 */
@Configuration
@ConditionalOnProperty(name = "spring.ai.openai.api-key", matchIfMissing = false)
public class LlmConfig {

    @Bean
    public ChatClient chatClient(@Qualifier("deepSeekChatModel") ChatModel chatModel) {
        return ChatClient.builder(chatModel).build();
    }

    @Bean
    public KnowPostDescriptionService knowPostDescriptionService(ChatClient chatClient) {
        return new KnowPostDescriptionServiceImpl(chatClient);
    }
}